"""Independent, bounded translation of the pinned Google model's 11 TFLite ops to Core ML MIL.
Build-time tooling only. Unsupported graphs/options fail rather than approximating operators.
"""
from pathlib import Path
import hashlib,json,sys
import numpy as np
import tflite
import coremltools as ct
from coremltools.converters.mil import Builder as mb
r=Path(sys.argv[1])
raw=(r/'selfie_multiclass_256x256.tflite').read_bytes()
assert hashlib.sha256(raw).hexdigest()=='c6748b1253a99067ef71f7e26ca71096cd449baefa8f101900ea23016507e0e0'
model=tflite.Model.GetRootAsModel(raw,0);assert model.SubgraphsLength()==1;g=model.Subgraphs(0)
names={v:k for k,v in vars(tflite.BuiltinOperator).items() if isinstance(v,int)}
options={v:k for k,v in vars(tflite.BuiltinOptions).items() if isinstance(v,int)}
def const(i):
 t=g.Tensors(int(i));b=model.Buffers(t.Buffer());assert b.DataLength()>0
 dtype={0:np.float32,2:np.int32}[t.Type()]
 return np.frombuffer(bytes(b.DataAsNumpy()),dtype=dtype).reshape(t.ShapeAsNumpy()).copy()
def shape(i):return tuple(int(x) for x in g.Tensors(int(i)).ShapeAsNumpy())
def nchw(x):return mb.transpose(x=x,perm=[0,3,1,2])
def nhwc(x):return mb.transpose(x=x,perm=[0,2,3,1])
def activation(x,kind):
 if kind==0:return x
 if kind==1:return mb.relu(x=x)
 raise ValueError('Unsupported activation '+str(kind))
@mb.program(input_specs=[mb.TensorSpec(shape=(1,256,256,3))],opset_version=ct.target.macOS14)
def program(image):
 values={0:image}
 def value(i):
  i=int(i)
  if i not in values:values[i]=const(i)
  return values[i]
 for index in range(g.OperatorsLength()):
  op=g.Operators(index);kind=names[model.OperatorCodes(op.OpcodeIndex()).BuiltinCode()]
  ins=[int(x) for x in op.InputsAsNumpy()];outs=[int(x) for x in op.OutputsAsNumpy()];assert len(outs)==1
  table=op.BuiltinOptions();o=getattr(tflite,options[op.BuiltinOptionsType()])() if table else None
  if o:o.Init(table.Bytes,table.Pos)
  if kind in ['CONV_2D','DEPTHWISE_CONV_2D']:
   assert o.Padding() in [0,1]
   w=const(ins[1]);groups=1
   if kind=='CONV_2D':w=np.transpose(w,(0,3,1,2))
   else:
    assert o.DepthMultiplier()==1;groups=shape(ins[0])[-1];w=np.transpose(w,(3,0,1,2))
   result=mb.conv(x=nchw(value(ins[0])),weight=w,bias=const(ins[2]),strides=[o.StrideH(),o.StrideW()],dilations=[o.DilationHFactor(),o.DilationWFactor()],pad_type='same' if o.Padding()==0 else 'valid',groups=groups)
   result=nhwc(activation(result,o.FusedActivationFunction()))
  elif kind in ['ADD','MUL']:
   result=(mb.add if kind=='ADD' else mb.mul)(x=value(ins[0]),y=value(ins[1]));result=activation(result,o.FusedActivationFunction())
  elif kind=='RESHAPE':result=mb.reshape(x=value(ins[0]),shape=const(ins[1]))
  elif kind=='TRANSPOSE':result=mb.transpose(x=value(ins[0]),perm=const(ins[1]))
  elif kind=='SOFTMAX':
   assert o.Beta()==1.0;result=mb.softmax(x=value(ins[0]),axis=-1)
  elif kind=='SUM':result=mb.reduce_sum(x=value(ins[0]),axes=np.atleast_1d(const(ins[1])),keep_dims=o.KeepDims())
  elif kind=='RESIZE_BILINEAR':
   assert not o.AlignCorners() and o.HalfPixelCenters()
   height,width=[int(x) for x in const(ins[1])]
   result=nhwc(mb.resize_bilinear(x=nchw(value(ins[0])),target_size_height=height,target_size_width=width,sampling_mode='UNALIGN_CORNERS'))
  elif kind=='RESIZE_NEAREST_NEIGHBOR':
   assert not o.AlignCorners() and o.HalfPixelCenters()
   height,width=[int(x) for x in const(ins[1])];old=shape(ins[0]);assert height%old[1]==0 and width%old[2]==0
   # Integer enlargement: floor((i+0.5)/scale) == floor(i/scale).
   result=nhwc(mb.upsample_nearest_neighbor(x=nchw(value(ins[0])),scale_factor_height=height//old[1],scale_factor_width=width//old[2]))
  elif kind=='TRANSPOSE_CONV':
   assert o.Padding()==0 and o.StrideH()==2 and o.StrideW()==2
   w=const(ins[1]);assert w.shape[1:3]==(2,2)
   output=const(ins[0]);output=output[[0,3,1,2]]
   result=nhwc(mb.conv_transpose(x=nchw(value(ins[2])),weight=np.transpose(w,(3,0,1,2)),bias=const(ins[3]),strides=[2,2],pad_type='valid',output_shape=output))
   result=activation(result,o.FusedActivationFunction())
  else:raise ValueError('Unsupported '+kind)
  assert result.shape==shape(outs[0]),(index,kind,result.shape,shape(outs[0]))
  values[outs[0]]=result
 return mb.identity(x=values[int(g.Outputs(0))],name='logits')
print('MIL graph built',flush=True)
converted=ct.convert(program,minimum_deployment_target=ct.target.macOS14,compute_precision=ct.precision.FLOAT32,compute_units=ct.ComputeUnit.CPU_ONLY)
converted.author='Google / MediaPipe; native Core ML conversion by Photato'
converted.license='Apache-2.0; original model card: https://storage.googleapis.com/mediapipe-assets/Model%20Card%20Multiclass%20Segmentation.pdf'
converted.short_description='Six-class person feature segmentation. Input NHWC RGB normalized (byte-127.5)/127.5; output NHWC logits.'
converted.user_defined_metadata.update({'photato.model':'people-parts-v1','photato.source.sha256':hashlib.sha256(raw).hexdigest(),'photato.classes':'background,hair,bodySkin,faceSkin,clothes,accessories','photato.input.mean':'127.5','photato.input.std':'127.5','photato.conversion':'independent-pinned-tflite-to-mil-fp32'})
path=r/'PeopleParts.mlpackage';converted.save(str(path));print('Saved',path,flush=True)
