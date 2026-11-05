#!/usr/bin/env python3
"""Owned declarative stacking vectors; no Swift/Rust or production permutation code."""
from pathlib import Path
import itertools,json
root=Path(__file__).resolve().parent.parent
cases=[]
for background in [False,True]:
 order=(['BG']if background else[])+list('ABCDE');minimum=int(background);size=len(order)
 for count in range(1,6):
  for chosen in itertools.combinations(range(minimum,size),count):
   selected=set(chosen)
   for operation in ['bringToFront','bringForward','sendBackward','sendToBack','reverse']:
    values=[order[i]for i in chosen]
    if operation=='bringToFront':positions=list(range(size-count,size))
    elif operation=='sendToBack':positions=list(range(minimum,minimum+count))
    elif operation=='bringForward':positions=[i+int(any(j>i and j not in selected for j in range(minimum,size)))for i in chosen]
    elif operation=='sendBackward':positions=[i-int(any(j<i and j not in selected for j in range(minimum,size)))for i in chosen]
    else:positions=list(chosen);values.reverse()
    placed=dict(zip(positions,values));remaining=iter(value for i,value in enumerate(order)if i not in selected)
    result=[placed[i]if i in placed else next(remaining)for i in range(size)]
    cases.append({'background':background,'selected':[order[i]for i in chosen],'operation':operation,'order':result})
output=root/'Tests/PhotoCraftCoreTests/Fixtures/LayerStack/stack-order.json';output.parent.mkdir(parents=True,exist_ok=True)
output.write_text(json.dumps({'license':'MIT OR Apache-2.0','origin':'Owned declarative selected-rank vectors, Python stdlib only; no production codec or permutation code imported.','reference':'https://helpx.adobe.com/photoshop/desktop/create-manage-layers/transform-manipulate-layers/reorder-and-move-layers.html','method':'Place selected items at their target rank coordinates, then fill remaining ranks with original unselected items. One-slot motion uses existence of an unselected sibling above/below.','scope':'Exhaustive five-layer sibling subsets with and without an anchored Background. Not a Photoshop-produced file or independent Photoshop pixel comparison.','cases':cases},indent=2)+'\n')
print(json.dumps({'cases':len(cases),'output':str(output)}))
