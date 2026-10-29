"""Compare the pinned original graph with the converted Core ML graph before packaging."""
from pathlib import Path
import sys,json
import numpy as np
import tensorflow as tf
import coremltools as ct
r=Path(sys.argv[1]);reference=tf.lite.Interpreter(model_path=str(r/'selfie_multiclass_256x256.tflite'),num_threads=4,experimental_op_resolver_type=tf.lite.experimental.OpResolverType.BUILTIN_WITHOUT_DEFAULT_DELEGATES);reference.allocate_tensors()
rng=np.random.default_rng(198);inputs=[np.zeros((1,256,256,3),np.float32),np.full((1,256,256,3),-1,np.float32),np.ones((1,256,256,3),np.float32),rng.uniform(-1,1,(1,256,256,3)).astype(np.float32)]
def softmax(x):
 e=np.exp(x-x.max(-1,keepdims=True));return e/e.sum(-1,keepdims=True)
records=[]
for mode,unit in [('CPU_ONLY',ct.ComputeUnit.CPU_ONLY),('ALL',ct.ComputeUnit.ALL)]:
 model=ct.models.MLModel(str(r/'PeopleParts.mlpackage'),compute_units=unit)
 for index,image in enumerate(inputs):
  reference.set_tensor(0,image);reference.invoke();expected=reference.get_tensor(372);actual=model.predict({'image':image})['logits'];p=softmax(expected);q=softmax(actual)
  error=float(np.max(np.abs(expected-actual)));prob=float(np.max(np.abs(p-q)));mean=float(np.mean(np.abs(p-q)));agreement=float(np.mean(p.argmax(-1)==q.argmax(-1)))
  assert np.isfinite(actual).all() and error<0.002 and prob<0.001 and mean<0.00001 and agreement>=0.9999,(mode,index,error,prob,mean,agreement)
  records.append(dict(mode=mode,input=index,maxLogitError=error,maxProbabilityError=prob,meanProbabilityError=mean,classAgreement=agreement))
(r/'validation.json').write_text(json.dumps({'passed':True,'cases':records,'scope':'Pinned original TFLite vs native Core ML; not Photoshop equivalence.'},indent=2)+'\n')
