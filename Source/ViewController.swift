import UIKit
import Metal
import MetalKit

var control = Control()
var cBuffer:MTLBuffer! = nil
var iBuffer:MTLBuffer! = nil        // 256 * float3

class ViewController: UIViewController {
    var timer = Timer()
    var outTexture: MTLTexture!
    var pipeline1: MTLComputePipelineState!
    let queue = DispatchQueue(label: "Inflection")
    lazy var device: MTLDevice! = MTLCreateSystemDefaultDevice()
    lazy var defaultLibrary: MTLLibrary! = { self.device.makeDefaultLibrary() }()
    lazy var commandQueue: MTLCommandQueue! = { return self.device.makeCommandQueue() }()
    let threadGroupCount = MTLSizeMake(16, 16, 1)
    lazy var threadGroups: MTLSize = { MTLSizeMake(Int(self.outTexture.width) / self.threadGroupCount.width, Int(self.outTexture.height) / self.threadGroupCount.height, 1) }()
    
    var inflection = Array(repeating:float3(), count:256)
    var iIndex:Int32 = 0
    var iInfX:Float = 0
    var iInfY:Float = 0
    var iInfZ:Float = 0
    var needsPaint:Bool = false
    
    let inflectionSize = MemoryLayout<float3>.stride * Int(MAXCOUNT)
    let centerMin:Float = -15
    let centerMax:Float = +15
    let zoomMin:Float = 0.001
    let zoomMax:Float = 0.01
    
    @IBOutlet var imageView: UIImageView!
    @IBOutlet var positionXY: DeltaView!
    @IBOutlet var positionZ: SliderView!
    @IBOutlet var inflectionXY: DeltaView!
    @IBOutlet var inflectionZ: SliderView!
    
    func alterInflectionCount(_ dir:Int32) {
        control.count = iClamp(control.count + dir,0,20)
        alterInflectionIndex(0)
    }

    func alterInflectionIndex(_ dir:Int32) {
        iIndex = iClamp(iIndex + dir,0,control.count-1)
        if iIndex < 0 { iIndex = 0 }
        
        let ii = Int(iIndex)
        iInfX = inflection[ii].x
        iInfY = inflection[ii].y
        iInfZ = inflection[ii].z

        inflectionXY.initializeFloat1(&iInfX, centerMin, centerMax, 0.2, "Inflect XY")
        inflectionXY.initializeFloat2(&iInfY)
        inflectionZ.initializeFloat(&iInfZ, .delta, centerMin, centerMax, 0.2, "Inflect Z")
        
        infCountLabel.text = String(format:"I Count %2d", Int(control.count))
        infIndexLabel.text = String(format:"I Index %2d", Int(iIndex + 1))  // base 1 display
        inflectionXY.setNeedsDisplay()
        inflectionZ.setNeedsDisplay()
    }

    @IBAction func infCountMinus(_ sender: UIButton) { alterInflectionCount(-1) }
    @IBAction func infCountPlus(_ sender: UIButton)  { alterInflectionCount(+1) }
    @IBAction func infIndexMinus(_ sender: UIButton) { alterInflectionIndex(-1) }
    @IBAction func infIndexPlus(_ sender: UIButton)  { alterInflectionIndex(+1) }

    @IBOutlet var infCountLabel: UILabel!
    @IBOutlet var infIndexLabel: UILabel!
    
    func initialize() {
        positionXY.initializeFloat1(&control.centerX, centerMin, centerMax, 2, "Center")
        positionXY.initializeFloat2(&control.centerY)
        positionZ.initializeFloat(&control.zoom, .delta, zoomMin, zoomMax, 0.01, "Zoom")
   }
    
    //MARK: -
//    bool centering;
//    bool julia;
//    int count;
//    vector_float2 center;
//    vector_float2 radius;
//    vector_float2 aspect;
//    vector_float3 dragging;

    
    func reset() {
        iIndex = 0
        control.count = 0
        control.centerX = 3.426
        control.centerY = -2.9556
        control.zoom = 0.0052
        control.radiusX = 0.01
        control.radiusY = 0.006

        positionXY.setNeedsDisplay()
        positionZ.setNeedsDisplay()
        alterInflectionIndex(0)

        for i in 0 ..< MAXCOUNT { inflection[Int(i)] = float3(0,0,0.01) }
        
        needsPaint = true
    }
    
    //MARK: -

    @IBAction func resetButtonPressed(_ sender: UIButton) { reset() }

    override var prefersStatusBarHidden: Bool { return true }

    //MARK: -
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        do {
            guard let kf1 = defaultLibrary.makeFunction(name: "inflectionShader")  else { fatalError() }
            pipeline1 = try device.makeComputePipelineState(function: kf1)
        }
        catch { fatalError("error creating pipelines") }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: Int(SIZE),
            height: Int(SIZE),
            mipmapped: false)
        outTexture = self.device.makeTexture(descriptor: textureDescriptor)!
        
        initialize()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        cBuffer = device.makeBuffer(bytes: &control, length: MemoryLayout<Control>.stride, options: MTLResourceOptions.storageModeShared)
        iBuffer = device.makeBuffer(bytes: &inflection, length:inflectionSize, options: MTLResourceOptions.storageModeShared)

        reset()
        needsPaint = true
        timer = Timer.scheduledTimer(timeInterval: 1.0/20.0, target:self, selector: #selector(timerHandler), userInfo: nil, repeats:true)
    }
    
    //MARK: -
    
    @objc func timerHandler() {
        if positionXY.update() { needsPaint = true }
        if positionZ.update() { needsPaint = true }
        if inflectionXY.update() { needsPaint = true }
        if inflectionZ.update() { needsPaint = true }

        if needsPaint {
            needsPaint = false
            updateImage()
        }
    }
    
    //MARK: -
    
    func updateImage() {
        queue.async {
            self.calcInflection()
            DispatchQueue.main.async { self.imageView.image = self.image(from: self.outTexture) }
        }
    }
    
//    func alterZoom(_ amt:Float) {
//        let xc:Float = control.base.x + Float(imageView.bounds.width / 2) / control.zoom
//        let yc:Float = control.base.y + Float(imageView.bounds.height / 2) / control.zoom
//        
//        control.zoom *= amt
//        
//        let min:Float = 150
//        if control.zoom < min { control.zoom = min }
//        
//        //Swift.print("Zoom ",control.zoom)
//        
//        control.base.x = xc - Float(imageView.bounds.width / 2) / control.zoom
//        control.base.y = yc - Float(imageView.bounds.height / 2) / control.zoom
//        
//        needsPaint = true
//    }
    
    //MARK: -

    func calcInflection() {
        
        control.centering = true
        control.julia = true
        control.sCenter.x = -control.centerX
        control.sCenter.y = control.centerY

        let ii = Int(iIndex)
        inflection[ii].x = iInfX
        inflection[ii].y = iInfY
        inflection[ii].z = iInfZ

//        control.dragging = float3(0,0,0)
        
        iBuffer.contents().copyBytes(from: &inflection, count:inflectionSize)
        cBuffer.contents().copyBytes(from: &control, count:MemoryLayout<Control>.stride)
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        commandEncoder.setComputePipelineState(pipeline1)
        commandEncoder.setTexture(outTexture, index: 0)
        commandEncoder.setBuffer(cBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(iBuffer, offset: 0, index: 1)
        commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
        commandEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    //MARK: -
    
    @IBAction func tapGesture(_ sender: UITapGestureRecognizer) {
        //        let t = sender.location(in: nil)
        //        tapScrollX = Float(t.x - self.imageView.bounds.width/2)  / (control.zoom * Float(12))
        //        tapScrollY = Float(t.y - self.imageView.bounds.height/2) / (control.zoom * Float(12))
        //        tapScrollCount = 10
    }
    
    @IBAction func panGesture(_ sender: UIPanGestureRecognizer) {
        //        let t = sender.translation(in: self.view)
    }
    
    @IBAction func pinchGesture(_ sender: UIPinchGestureRecognizer) {
        //        var t = Float(sender.scale)
        //        t = Float(1) - (Float(1) - t) / Float(20)
        
        //Swift.print("Pinch gesture ",t)
        
        //        alterZoom(t)
    }
    
    //MARK: -
    // edit Scheme, Options, Metal API Validation : Disabled
    //the fix is to turn off Metal API validation under Product -> Scheme -> Options
    
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


