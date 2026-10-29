import Foundation

// Native Swift translation of PhotoCraft segment/maxflow.rs (MIT OR Apache-2.0).
// Boykov–Kolmogorov growing trees, augmentation and orphan adoption.
private struct SelectionQueue {
  var values:[Int]=[],offset=0,front:[Int]=[]
  mutating func append(_ value:Int){values.append(value)}
  mutating func prepend(_ value:Int){front.append(value)}
  mutating func pop()->Int? {
    if let v=front.popLast(){return v}
    guard offset<values.count else{return nil}
    let v=values[offset];offset+=1
    if offset>4096 && offset*2>values.count {values.removeFirst(offset);offset=0}
    return v
  }
}
final class SelectionGraph {
  private static let none = -1,terminal = -2,orphan = -3,eps:Float=1e-5
  private var first:[Int],terminalCapacity:[Float],parent:[Int],sink:[Bool],stamp:[Int],distance:[Int],active:[Bool]
  private var head:[Int]=[],next:[Int]=[],capacity:[Float]=[]
  private(set) var flow=0.0
  init(nodes:Int,edges:Int) {
    first=Array(repeating:Self.none,count:nodes);terminalCapacity=Array(repeating:0,count:nodes)
    parent=first;sink=Array(repeating:false,count:nodes);stamp=Array(repeating:0,count:nodes);distance=stamp;active=sink
    head.reserveCapacity(edges*2);next.reserveCapacity(edges*2);capacity.reserveCapacity(edges*2)
  }
  func addTerminal(_ i:Int,source:Float,sink:Float) {
    let delta=terminalCapacity[i];var s=source,t=sink
    if delta>0 {s+=delta}else{t-=delta};flow+=Double(min(s,t));terminalCapacity[i]=s-t
  }
  func addEdge(_ i:Int,_ j:Int,capacity c:Float,reverse:Float) {
    let a=head.count;head.append(j);next.append(first[i]);capacity.append(c);first[i]=a
    head.append(i);next.append(first[j]);capacity.append(reverse);first[j]=a+1
  }
  func inSource(_ i:Int)->Bool {parent[i] != Self.none && !sink[i]}
  @discardableResult func maxflow()throws->Double {
    var queue=SelectionQueue(),orphans=SelectionQueue(),time=0,ticks=0
    for i in first.indices {
      active[i]=false;stamp[i]=0
      if abs(terminalCapacity[i])>Self.eps {sink[i]=terminalCapacity[i]<0;parent[i]=Self.terminal;distance[i]=1;active[i]=true;queue.append(i)}else{parent[i]=Self.none}
    }
    while let i=queue.pop() {
      ticks+=1;if ticks%1024==0 {try Task.checkCancellation()}
      active[i]=false;if parent[i]==Self.none {continue}
      var contact=Self.none,a=first[i];let isSink=sink[i]
      while a != Self.none {
        let j=head[a],c=capacity[isSink ? a^1:a]
        if c>Self.eps {
          if parent[j]==Self.none {
            sink[j]=isSink;parent[j]=a^1;stamp[j]=stamp[i];distance[j]=distance[i]+1
            if !active[j] {active[j]=true;queue.append(j)}
          } else if sink[j] != isSink {contact=isSink ? a^1:a;break}
          else if stamp[j]<=stamp[i] && distance[j]>distance[i] {parent[j]=a^1;stamp[j]=stamp[i];distance[j]=distance[i]+1}
        }
        a=next[a]
      }
      if contact==Self.none {continue}
      if !active[i] {active[i]=true;queue.prepend(i)}
      time+=1;augment(contact,orphans:&orphans)
      while let o=orphans.pop(){ticks+=1;if ticks%1024==0{try Task.checkCancellation()};adopt(o,time:time,queue:&queue,orphans:&orphans)}
    }
    try Task.checkCancellation();return flow
  }
  private func augment(_ m:Int,orphans:inout SelectionQueue) {
    let u=head[m^1],v=head[m];var b=capacity[m],x=u
    while parent[x] != Self.terminal {let a=parent[x];b=min(b,capacity[a^1]);x=head[a]};b=min(b,terminalCapacity[x]);x=v
    while parent[x] != Self.terminal {let a=parent[x];b=min(b,capacity[a]);x=head[a]};b=min(b,-terminalCapacity[x])
    capacity[m^1]+=b;capacity[m]-=b;x=u
    while parent[x] != Self.terminal {
      let a=parent[x],up=head[a];capacity[a]+=b;capacity[a^1]-=b
      if capacity[a^1]<=Self.eps {parent[x]=Self.orphan;orphans.append(x)};x=up
    }
    terminalCapacity[x]-=b;if terminalCapacity[x]<=Self.eps {parent[x]=Self.orphan;orphans.append(x)};x=v
    while parent[x] != Self.terminal {
      let a=parent[x],up=head[a];capacity[a^1]+=b;capacity[a]-=b
      if capacity[a]<=Self.eps {parent[x]=Self.orphan;orphans.append(x)};x=up
    }
    terminalCapacity[x]+=b;if terminalCapacity[x] >= -Self.eps {parent[x]=Self.orphan;orphans.append(x)};flow+=Double(b)
  }
  private func adopt(_ i:Int,time:Int,queue:inout SelectionQueue,orphans:inout SelectionQueue) {
    let isSink=sink[i];var best=Self.none,minimum=Int.max,a=first[i]
    while a != Self.none {
      let c=capacity[isSink ? a:a^1],j=head[a]
      if c>Self.eps && sink[j]==isSink && parent[j] != Self.none {
        var d=0,k=j
        while true {
          if stamp[k]==time {d+=distance[k];break}
          let pa=parent[k];d+=1
          if pa==Self.terminal {stamp[k]=time;distance[k]=1;break}
          if pa==Self.orphan {d=Int.max;break};k=head[pa]
        }
        if d<Int.max {
          if d<minimum {best=a;minimum=d};k=j;var dd=d
          while stamp[k] != time {stamp[k]=time;distance[k]=dd;dd-=1;k=head[parent[k]]}
        }
      }
      a=next[a]
    }
    if best != Self.none {parent[i]=best;stamp[i]=time;distance[i]=minimum+1;return}
    parent[i]=Self.none;a=first[i]
    while a != Self.none {
      let j=head[a],pj=parent[j]
      if sink[j]==isSink && pj != Self.none {
        let c=capacity[isSink ? a:a^1]
        if c>Self.eps && !active[j] {active[j]=true;queue.append(j)}
        if pj != Self.terminal && pj != Self.orphan && head[pj]==i {parent[j]=Self.orphan;orphans.append(j)}
      }
      a=next[a]
    }
  }
}
