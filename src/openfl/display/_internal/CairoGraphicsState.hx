package openfl.display._internal;

#if !flash
import openfl.display._internal.CairoGraphics.Scale9GridBounds;
import openfl.display._internal.DrawCommandBuffer;
import openfl.display.BitmapData;
import openfl.display.Graphics;
import openfl.geom.Matrix;
import openfl.geom.Rectangle;
#if lime
import lime.graphics.cairo.Cairo;
import lime.graphics.cairo.CairoPattern;
import lime.math.Matrix3;
#end

/**
 * Per-renderer scratch state for CairoGraphics.
 * Each CairoRenderer owns an instance, so render and hitTest
 * on different threads never share mutable state.
 */
@SuppressWarnings("checkstyle:FieldDocComment")
class CairoGraphicsState
{
	#if lime_cairo
	public var allowSmoothing:Bool;
	public var bitmapFill:BitmapData;
	public var bitmapFillMatrix:Matrix;
	public var bitmapRepeat:Bool;
	public var bitmapStroke:BitmapData;
	public var bitmapStrokeMatrix:Matrix;
	public var bounds:Rectangle;
	public var cairo:Cairo;
	public var fillCommands:DrawCommandBuffer = new DrawCommandBuffer();
	public var fillPattern:CairoPattern;
	public var fillScale9Bounds:Scale9GridBounds;
	public var graphics:Graphics;
	public var hasFill:Bool;
	public var hasStroke:Bool;
	public var hitTesting:Bool;
	public var inversePendingMatrix:Matrix;
	public var pendingMatrix:Matrix;
	public var strokeCommands:DrawCommandBuffer = new DrawCommandBuffer();
	public var strokePattern:CairoPattern;
	public var strokeScale9Bounds:Scale9GridBounds;
	public var tempMatrix3 = new Matrix3();
	public var worldAlpha:Float;
	#end

	public function new() {}
}
#end
