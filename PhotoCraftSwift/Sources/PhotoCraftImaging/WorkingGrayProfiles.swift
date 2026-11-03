import Foundation
import PhotoCraftCore

/// An independently framed ICC gray profile. Only numerical tone-response data
/// from an owned interoperability document is used; no vendor ICC binary, text
/// tags or executable code is bundled. See the selection-luminosity provenance.
public enum WorkingGrayProfiles {
  public static let dotGain20:Data = makeDotGain20()
  private static let response:[UInt16] = [
    0,16,32,48,64,80,97,127,160,197,236,279,324,373,424,478,
    534,594,656,720,787,857,929,1004,1081,1160,1242,1326,1413,1502,1593,1686,
    1782,1879,1979,2082,2186,2292,2401,2512,2625,2740,2857,2976,3098,3221,3346,3474,
    3603,3734,3868,4003,4140,4280,4421,4564,4709,4856,5005,5156,5309,5463,5620,5778,
    5938,6100,6264,6430,6598,6767,6939,7112,7286,7463,7642,7822,8004,8188,8373,8561,
    8750,8941,9133,9328,9524,9721,9921,10122,10325,10530,10736,10944,11154,11365,11578,11793,
    12010,12228,12448,12669,12892,13117,13343,13571,13801,14032,14265,14500,14736,14974,15213,15454,
    15697,15941,16187,16435,16684,16934,17186,17440,17695,17952,18211,18471,18733,18996,19260,19527,
    19795,20064,20335,20607,20881,21157,21434,21713,21993,22274,22558,22842,23128,23416,23705,23996,
    24288,24582,24877,25174,25472,25772,26073,26376,26680,26985,27293,27601,27911,28223,28536,28850,
    29166,29483,29802,30122,30444,30767,31092,31418,31745,32074,32405,32737,33070,33404,33741,34078,
    34417,34757,35099,35442,35787,36133,36481,36829,37180,37531,37885,38239,38595,38952,39311,39671,
    40032,40395,40759,41125,41492,41861,42230,42601,42974,43348,43723,44100,44478,44857,45238,45620,
    46004,46388,46775,47162,47551,47941,48333,48726,49120,49516,49913,50311,50711,51112,51515,51918,
    52323,52730,53138,53547,53957,54369,54782,55196,55612,56029,56447,56867,57288,57710,58134,58559,
    58985,59412,59841,60271,60703,61136,61570,62005,62442,62880,63319,63760,64202,64645,65089,65535
  ]
  private static func makeDotGain20()->Data {
    func n(_ value:Int,_ width:Int)->Data {Data((0..<width).reversed().map{UInt8(truncatingIfNeeded:value>>($0*8))})}
    func text(_ value:String)->Data {Data(value.utf8)}
    func xyz(_ values:[Int])->Data {text("XYZ ")+Data(repeating:0,count:4)+values.reduce(Data()){$0+n($1,4)}}
    let name=Data("Dot Gain 20%".utf8)+Data([0])
    let description=text("desc")+Data(repeating:0,count:4)+n(name.count,4)+name+Data(repeating:0,count:78)
    let copyright=text("text")+Data(repeating:0,count:4)+text("Photato numeric gray profile. MIT OR Apache-2.0.")+Data([0])
    let trc=text("curv")+Data(repeating:0,count:4)+n(response.count,4)+response.reduce(Data()){$0+n(Int($1),2)}
    let entries:[(String,Data)]=[("desc",description),("cprt",copyright),("wtpt",xyz([0xf6d6,0x10000,0xd32d])),("bkpt",xyz([0,0,0])),("kTRC",trc)]
    var header=Data(repeating:0,count:128)
    func put(_ offset:Int,_ data:Data) {header.replaceSubrange(offset..<offset+data.count,with:data)}
    put(8,n(0x02100000,4));put(12,text("mntrGRAYXYZ "));put(24,n(2000,2)+n(1,2)+n(1,2))
    put(36,text("acspAPPL"));put(48,text("FI  DG20"));put(64,n(1,4));put(68,xyz([0xf6d6,0x10000,0xd32d]).dropFirst(8));put(80,text("PHTO"))
    var table=n(entries.count,4),payload=Data()
    for (key,data) in entries {
      table+=text(key)+n(132+entries.count*12+payload.count,4)+n(data.count,4)
      payload+=data;payload+=Data(repeating:0,count:(4-data.count%4)%4)
    }
    put(0,n(128+table.count+payload.count,4));return header+table+payload
  }
}
