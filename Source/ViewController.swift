import UIKit
import Metal
import MetalKit

extension Control {
    init() {
        centering = true
        julia = true
        inflectionCount = 0
        centerX = 0;  centerY = 0
        sCenter = float2()
        zoom = 0
        color1r = 0;  color1g = 0;  color1b = 0
        color2r = 1;  color2g = 1;  color2b = 1
    }
}

// used during development of screenRotated() layout routine to simulate other iPad sizes
//let scrnSz:[CGPoint] = [ CGPoint(x:768,y:1024), CGPoint(x:834,y:1112), CGPoint(x:1024,y:1366) ] // portrait 9.7, 10.5, 12.9" iPads
//let scrnIndex = 0
//let scrnLandscape:Bool = true

class ViewController: UIViewController {
    var control = Control()
    var cBuffer:MTLBuffer! = nil
    var iBuffer:MTLBuffer! = nil
    
    var outTexture: MTLTexture!
    var pipeLine: MTLComputePipelineState!
    let queue = DispatchQueue(label: "Inflection")
    lazy var device: MTLDevice! = MTLCreateSystemDefaultDevice()
    lazy var defaultLibrary: MTLLibrary! = { self.device.makeDefaultLibrary() }()
    lazy var commandQueue: MTLCommandQueue! = { return self.device.makeCommandQueue() }()
    let threadGroupCount = MTLSizeMake(20,20, 1)
    lazy var threadGroups: MTLSize = { MTLSizeMake(Int(self.outTexture.width) / self.threadGroupCount.width, Int(self.outTexture.height) / self.threadGroupCount.height, 1) }()
    
    var timer = Timer()
    var sList:[SliderView]! = nil
    var dList:[DeltaView]! = nil
    var inflection = Array(repeating:float3(0,0,0.01), count:Int(MAX_INFLECTIONS))
    var iIndex:Int32 = 0
    var iInfX:Float = 0
    var iInfY:Float = 0
    var iInfZ:Float = 0
    var needsPaint:Bool = false
    
    let inflectionSize = MemoryLayout<float3>.stride * Int(MAX_INFLECTIONS)
    let centerMin:Float = -15
    let centerMax:Float = +15
    let zoomMin:Float = 0.001
    let zoomMax:Float = 0.01
    
    @IBOutlet var imageView: UIImageView!
    @IBOutlet var positionXY: DeltaView!
    @IBOutlet var positionZ: SliderView!
    @IBOutlet var inflectionXY: DeltaView!
    @IBOutlet var inflectionZ: SliderView!
    @IBOutlet var color1XY: DeltaView!
    @IBOutlet var color1Z: SliderView!
    @IBOutlet var color2XY: DeltaView!
    @IBOutlet var color2Z: SliderView!
    
    @IBOutlet var iCMButton: UIButton!
    @IBOutlet var iCPButton: UIButton!
    @IBOutlet var iIMButton: UIButton!
    @IBOutlet var iIPButton: UIButton!
    @IBOutlet var resetButton: UIButton!
    @IBOutlet var helpButton: UIButton!
    @IBOutlet var iCLabel: UILabel!
    @IBOutlet var iILabel: UILabel!
    
    @IBAction func infCountMinus(_ sender: UIButton) { alterInflectionCount(-1) }
    @IBAction func infCountPlus(_ sender: UIButton)  { alterInflectionCount(+1) }
    @IBAction func infIndexMinus(_ sender: UIButton) { alterInflectionIndex(-1) }
    @IBAction func infIndexPlus(_ sender: UIButton)  { alterInflectionIndex(+1) }
    @IBAction func resetButtonPressed(_ sender: UIButton) { reset() }
    
    override var prefersStatusBarHidden: Bool { return true }
    
    //MARK: -
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        do {
            guard let kf1 = defaultLibrary.makeFunction(name: "inflectionShader")  else { fatalError() }
            pipeLine = try device.makeComputePipelineState(function: kf1)
        }
        catch { fatalError("error creating pipeline") }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: Int(SIZE),
            height: Int(SIZE),
            mipmapped: false)
        outTexture = self.device.makeTexture(descriptor: textureDescriptor)!
        
        sList = [ positionZ, inflectionZ, color1Z, color2Z ]
        dList = [ positionXY, inflectionXY, color1XY, color2XY ]

        positionXY.initializeFloat1(&control.centerX, centerMin, centerMax, 3, "Center")
        positionXY.initializeFloat2(&control.centerY)
        positionZ.initializeFloat(&control.zoom, .delta, zoomMin, zoomMax, 0.01, "Zoom")
        
        cBuffer = device.makeBuffer(bytes: &control, length: MemoryLayout<Control>.stride, options: MTLResourceOptions.storageModeShared)
        iBuffer = device.makeBuffer(bytes: &inflection, length:inflectionSize, options: MTLResourceOptions.storageModeShared)
        
        reset()
        timer = Timer.scheduledTimer(timeInterval: 1.0/20.0, target:self, selector: #selector(timerHandler), userInfo: nil, repeats:true)
        screenRotated()
    }
    
    //MARK: -
    
    @objc func timerHandler() {
        for s in sList { if s.update() { needsPaint = true }}
        for d in dList { if d.update() { needsPaint = true }}

        if needsPaint {
            needsPaint = false
            updateImage()
        }
    }
    
    //MARK: -
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { _ in
            self.screenRotated()
        }
    }
    
    @objc func screenRotated() {
        let xs:CGFloat = view.bounds.width
        let ys:CGFloat = view.bounds.height
//                let xs = scrnLandscape ? scrnSz[scrnIndex].y : scrnSz[scrnIndex].x
//                let ys = scrnLandscape ? scrnSz[scrnIndex].x : scrnSz[scrnIndex].y
        
        let fullWidth:CGFloat = 750
        let fullHeight:CGFloat = 200
        let ixs = xs - 4
        let iys = ys - fullHeight
        let cxs:CGFloat = 120   // slider width
        let bys:CGFloat = 35    // slider height
        let left:CGFloat = (xs - fullWidth)/2
        let by:CGFloat = iys + 10  // widget top
        var y:CGFloat = by
        var x:CGFloat = left
        
        imageView.frame = CGRect(x:2, y:0, width:ixs, height:iys)
        
        positionXY.frame = CGRect(x:x, y:y, width:cxs, height:cxs); y += cxs + 10
        positionZ.frame = CGRect(x:x, y:y, width:cxs, height:bys)
        x += cxs + 20
        y = by
        inflectionXY.frame = CGRect(x:x, y:y, width:cxs, height:cxs); y += cxs + 10
        inflectionZ.frame = CGRect(x:x, y:y, width:cxs, height:bys)
        x += cxs + 20
        y = by
        let x2 = x
        iCMButton.frame = CGRect(x:x, y:y, width:bys, height:bys);  x += bys + 10
        iCPButton.frame = CGRect(x:x, y:y, width:bys, height:bys);  x += bys + 10
        iCLabel.frame = CGRect(x:x, y:y, width:100, height:bys)
        x = x2
        y += bys + 10
        iIMButton.frame = CGRect(x:x, y:y, width:bys, height:bys);  x += bys + 10
        iIPButton.frame = CGRect(x:x, y:y, width:bys, height:bys);  x += bys + 10
        iILabel.frame = CGRect(x:x, y:y, width:100, height:bys)
        x = x2
        y += bys + 50
        resetButton.frame = CGRect(x:x, y:y, width:80, height:bys)
        helpButton.frame = CGRect(x:x + 110, y:y, width:80, height:bys)
        x += 200
        y = by
        color1XY.frame = CGRect(x:x, y:y, width:cxs, height:cxs); y += cxs + 10
        color1Z.frame = CGRect(x:x, y:y, width:cxs, height:bys)
        x += cxs + 20
        y = by
        color2XY.frame = CGRect(x:x, y:y, width:cxs, height:cxs); y += cxs + 10
        color2Z.frame = CGRect(x:x, y:y, width:cxs, height:bys)
    }
    
    //MARK: -
    
    func reset() {
        iIndex = 0
        control.inflectionCount = 0
        control.centerX = 3.426
        control.centerY = -2.9556
        control.zoom = 0.0052
        
        positionXY.setNeedsDisplay()
        positionZ.setNeedsDisplay()
        alterInflectionIndex(0)
        
        for i in 0 ..< Int(MAX_INFLECTIONS) { inflection[i] = float3(0,0,0.01) }
        needsPaint = true
    }
    
    func alterInflectionCount(_ dir:Int32) {
        control.inflectionCount = iClamp(control.inflectionCount + dir,0,MAX_INFLECTIONS - 1)
        alterInflectionIndex(0)
    }
    
    func alterInflectionIndex(_ dir:Int32) {
        iIndex = iClamp(iIndex + dir,0,control.inflectionCount-1)
        if iIndex < 0 { iIndex = 0 }
        
        let ii = Int(iIndex)
        iInfX = inflection[ii].x
        iInfY = inflection[ii].y
        iInfZ = inflection[ii].z
        
        inflectionXY.initializeFloat1(&iInfX, centerMin, centerMax, 0.5, "Inf XY")
        inflectionXY.initializeFloat2(&iInfY)
        inflectionZ.initializeFloat(&iInfZ, .delta, centerMin, centerMax, 0.5, "Inf Z")
        
        color1XY.initializeFloat1(&control.color1r, 0,1, 0.5, "C1")
        color1XY.initializeFloat2(&control.color1g)
        color1Z.initializeFloat(&control.color1b, .delta, 0,1, 0.5, "")
        color2XY.initializeFloat1(&control.color2r, 0,1, 0.5, "C2")
        color2XY.initializeFloat2(&control.color2g)
        color2Z.initializeFloat(&control.color2b, .delta, 0,1, 0.5, "")
        
        iCLabel.text = String(format:"I Count %2d", Int(control.inflectionCount))
        iILabel.text = String(format:"I Index %2d", Int(iIndex + 1))  // base 1 display
        inflectionXY.setNeedsDisplay()
        inflectionZ.setNeedsDisplay()
    }
    
    //MARK: -

    func calcInflection() {
        control.sCenter.x = -control.centerX
        control.sCenter.y = control.centerY

        let ii = Int(iIndex)
        inflection[ii].x = iInfX
        inflection[ii].y = iInfY
        inflection[ii].z = iInfZ

        iBuffer.contents().copyBytes(from: &inflection, count:inflectionSize)
        cBuffer.contents().copyBytes(from: &control, count:MemoryLayout<Control>.stride)
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        commandEncoder.setComputePipelineState(pipeLine)
        commandEncoder.setTexture(outTexture, index: 0)
        commandEncoder.setBuffer(cBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(iBuffer, offset: 0, index: 1)
        commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
        commandEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    func updateImage() {
        queue.async {
            self.calcInflection()
            DispatchQueue.main.async { self.imageView.image = self.image(from: self.outTexture) }
        }
    }
    
    //MARK: -
    // edit Scheme, Options, Metal API Validation : Disabled
    // the fix is to turn off Metal API validation under Product -> Scheme -> Options
    
    func image(from texture: MTLTexture) -> UIImage {
        let bytesPerPixel: Int = 4
        let imageByteCount = texture.width * texture.height * bytesPerPixel
        let bytesPerRow = texture.width * bytesPerPixel
        var src = [UInt8](repeating: 0, count: Int(imageByteCount))
        
        let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
        texture.getBytes(&src, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        let bitmapInfo = CGBitmapInfo(rawValue: (CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitsPerComponent = 8
        let context = CGContext(data: &src,
                                width: texture.width,
                                height: texture.height,
                                bitsPerComponent: bitsPerComponent,
                                bytesPerRow: bytesPerRow,
                                space: colorSpace,
                                bitmapInfo: bitmapInfo.rawValue)
        
        let dstImageFilter = context?.makeImage()
        return UIImage(cgImage: dstImageFilter!, scale: 0.0, orientation: UIImageOrientation.up)
    }
}

// -----------------------------------------------------------------

func fClamp(_ v:Float, _ range:float2) -> Float {
    if v < range.x { return range.x }
    if v > range.y { return range.y }
    return v
}

func fClamp(_ v:Float, _ min:Float, _ max:Float) -> Float {
    if v < min { return min }
    if v > max { return max }
    return v
}

func iClamp(_ v:Int32, _ min:Int32, _ max:Int32) -> Int32 {
    if v < min { return min }
    if v > max { return max }
    return v
}


