package openfl.display._internal;

#if !flash
import openfl.display._internal.CairoGraphicsState;
import openfl.display._internal.DrawCommandBuffer;
import openfl.display._internal.DrawCommandReader;
import openfl.display.BitmapData;
import openfl.display.CairoRenderer;
import openfl.display.GradientType;
import openfl.display.Graphics;
import openfl.display.InterpolationMethod;
import openfl.display.SpreadMethod;
import openfl.geom.Matrix;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import openfl.Vector;
#if lime
import lime.graphics.cairo.Cairo;
import lime.graphics.cairo.CairoExtend;
import lime.graphics.cairo.CairoFilter;
import lime.graphics.cairo.CairoImageSurface;
import lime.graphics.cairo.CairoPattern;
import lime.math.Matrix3;
import lime.math.Vector2;
#end

#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@:access(openfl.display.DisplayObject)
@:access(openfl.display.BitmapData)
@:access(openfl.display.Graphics)
@:access(openfl.geom.Matrix)
@:access(openfl.geom.Point)
@:access(openfl.geom.Rectangle)
@SuppressWarnings("checkstyle:FieldDocComment")
class CairoGraphics
{
	#if lime_cairo
	private static var SIN45:Float = 0.70710678118654752440084436210485;
	private static var TAN22:Float = 0.4142135623730950488016887242097;
	private static function closePath(s:CairoGraphicsState, strokeBefore:Bool = false):Void
	{
		if (s.strokePattern == null)
		{
			return;
		}

		if (!strokeBefore)
		{
			s.cairo.closePath();
		}

		if (!s.hitTesting)
		{
			var scale9Grid:Rectangle = s.graphics.__owner.__scale9Grid;
			#if (openfl_legacy_scale9grid && !cairo)
			var hasScale9Grid:Bool = false;
			#else
			var hasScale9Grid = scale9Grid != null && !s.graphics.__owner.__isMask && s.graphics.__worldTransform.b == 0 && s.graphics.__worldTransform.c == 0;
			#end

			if (s.bitmapStrokeMatrix != null || (hasScale9Grid && s.strokeScale9Bounds != null && s.bitmapStroke != null))
			{
				var matrix = Matrix.__pool.get();
				if (s.bitmapStrokeMatrix != null)
				{
					matrix.copyFrom(s.bitmapStrokeMatrix);
				}
				else
				{
					matrix.identity();
				}
				if (hasScale9Grid && s.strokeScale9Bounds != null && s.bitmapStroke != null)
				{
					var scaleX = s.strokeScale9Bounds.getScaleX();
					var scaleY = s.strokeScale9Bounds.getScaleY();
					if (scaleX > 0.0 && scaleY > 0.0)
					{
						matrix.scale(scaleX, scaleY);
					}
				}

				matrix.invert();
				s.strokePattern.matrix = matrix.__toMatrix3();
				Matrix.__pool.release(matrix);
			}
		}

		s.cairo.source = s.strokePattern;
		if (!s.hitTesting) s.cairo.strokePreserve();

		if (strokeBefore)
		{
			s.cairo.closePath();
		}

		s.cairo.newPath();
	}

	private static function createImagePattern(s:CairoGraphicsState, bitmapFill:BitmapData, bitmapRepeat:Bool, smooth:Bool):CairoPattern
	{
		var pattern = CairoPattern.createForSurface(bitmapFill.getSurface());
		pattern.filter = (smooth && s.allowSmoothing) ? CairoFilter.GOOD : CairoFilter.NEAREST;

		if (bitmapRepeat)
		{
			pattern.extend = CairoExtend.REPEAT;
		}
		else
		{
			// when flash doesn't repeat the image, it extends the pixels on the
			// edges to fill the remaining space, which is equivalent to the
			// CairoExtend.PAD option.
			pattern.extend = CairoExtend.PAD;
		}

		return pattern;
	}

	private static function createGradientPattern(s:CairoGraphicsState, type:GradientType, colors:Array<Int>, alphas:Array<Float>, ratios:Array<Int>, matrix:Matrix,
			spreadMethod:SpreadMethod, interpolationMethod:InterpolationMethod, focalPointRatio:Float):CairoPattern
	{
		var pattern:CairoPattern = null,
			point:Point = null,
			point2:Point = null,
			releaseMatrix = false;

		if (matrix == null)
		{
			matrix = Matrix.__pool.get();
			matrix.identity();
			releaseMatrix = true;
		}

		switch (type)
		{
			case RADIAL:
				focalPointRatio = focalPointRatio > 1.0 ? 1.0 : focalPointRatio < -1.0 ? -1.0 : focalPointRatio;

				// focal center
				point = Point.__pool.get();
				point.x = focalPointRatio * 819.2;
				point.y = 0.0;
				matrix.__transformPoint(point);

				// center
				point2 = Point.__pool.get();
				point2.setTo(0.0, 0.0);
				matrix.__transformPoint(point2);

				// end
				var point3 = Point.__pool.get();
				point3.x = 819.2;
				point3.y = 0.0;
				matrix.__transformPoint(point3);

				var scale9Grid:Rectangle = s.graphics.__owner.__scale9Grid;
				#if (openfl_legacy_scale9grid && !cairo)
				var hasScale9Grid:Bool = false;
				#else
				var hasScale9Grid = scale9Grid != null && !s.graphics.__owner.__isMask && s.graphics.__worldTransform.b == 0 && s.graphics.__worldTransform.c == 0;
				#end
				if (hasScale9Grid)
				{
					point.x = toScale9Position(s, point.x, scale9Grid.x, scale9Grid.width, s.bounds.width, s.graphics.__owner.scaleX);
					point.y = toScale9Position(s, point.y, scale9Grid.y, scale9Grid.height, s.bounds.height, s.graphics.__owner.scaleY);
					point2.x = toScale9Position(s, point2.x, scale9Grid.x, scale9Grid.width, s.bounds.width, s.graphics.__owner.scaleX);
					point2.y = toScale9Position(s, point2.y, scale9Grid.y, scale9Grid.height, s.bounds.height, s.graphics.__owner.scaleY);
					point3.x = toScale9Position(s, point3.x, scale9Grid.x, scale9Grid.width, s.bounds.width, s.graphics.__owner.scaleX);
					point3.y = toScale9Position(s, point3.y, scale9Grid.y, scale9Grid.height, s.bounds.height, s.graphics.__owner.scaleY);
				}

				var dx = point3.x - point2.x;
				var dy = point3.y - point2.y;

				Point.__pool.release(point3);

				// cairo can't draw ellipical radial gradients; they must be
				// circular. in other words, the same radius in both directions.
				// we basically take the average and use that. not ideal, but
				// probably as close as we can get to flash.
				var radius = Math.sqrt(dx * dx + dy * dy);

				point.x += s.graphics.__bounds.x;
				point2.x += s.graphics.__bounds.x;
				point.y += s.graphics.__bounds.y;
				point2.y += s.graphics.__bounds.y;

				pattern = CairoPattern.createRadial(point.x, point.y, 0.0, point2.x, point2.y, radius);

			case LINEAR:
				point = Point.__pool.get();
				point.setTo(-819.2, 0);
				matrix.__transformPoint(point);

				point2 = Point.__pool.get();
				point2.setTo(819.2, 0);
				matrix.__transformPoint(point2);

				var scale9Grid:Rectangle = s.graphics.__owner.__scale9Grid;
				#if (openfl_legacy_scale9grid && !cairo)
				var hasScale9Grid:Bool = false;
				#else
				var hasScale9Grid = scale9Grid != null && !s.graphics.__owner.__isMask && s.graphics.__worldTransform.b == 0 && s.graphics.__worldTransform.c == 0;
				#end
				if (hasScale9Grid)
				{
					point.x = toScale9Position(s, point.x, scale9Grid.x, scale9Grid.width, s.bounds.width, s.graphics.__owner.scaleX);
					point.y = toScale9Position(s, point.y, scale9Grid.y, scale9Grid.height, s.bounds.height, s.graphics.__owner.scaleY);
					point2.x = toScale9Position(s, point2.x, scale9Grid.x, scale9Grid.width, s.bounds.width, s.graphics.__owner.scaleX);
					point2.y = toScale9Position(s, point2.y, scale9Grid.y, scale9Grid.height, s.bounds.height, s.graphics.__owner.scaleY);
				}

				point.x += s.graphics.__bounds.x;
				point2.x += s.graphics.__bounds.x;
				point.y += s.graphics.__bounds.y;
				point2.y += s.graphics.__bounds.y;

				pattern = CairoPattern.createLinear(point.x, point.y, point2.x, point2.y);
		}

		var rgb:Int, alpha:Float, r:Float, g:Float, b:Float, ratio:Float;

		for (i in 0...colors.length)
		{
			rgb = colors[i];
			alpha = alphas[i];
			r = ((rgb & 0xFF0000) >>> 16) / 0xFF;
			g = ((rgb & 0x00FF00) >>> 8) / 0xFF;
			b = (rgb & 0x0000FF) / 0xFF;

			ratio = ratios[i] / 0xFF;
			if (ratio < 0) ratio = 0;
			else if (ratio > 1) ratio = 1;

			pattern.addColorStopRGBA(ratio, r, g, b, alpha);
		}

		if (point != null) Point.__pool.release(point);
		if (point2 != null) Point.__pool.release(point2);
		if (releaseMatrix) Matrix.__pool.release(matrix);

		var mat = pattern.matrix;

		mat.tx = s.bounds.x;
		mat.ty = s.bounds.y;

		pattern.matrix = mat;

		return pattern;
	}

	private static function drawRoundRect(s:CairoGraphicsState, x:Float, y:Float, width:Float, height:Float, ellipseWidth:Float, ellipseHeight:Null<Float>, ?scale9Grid:Rectangle,
			?scale9UnscaledWidth:Float, ?scale9UnscaledHeight:Float, ?scaleX:Float, ?scaleY:Float):Void
	{
		if (ellipseHeight == null) ellipseHeight = ellipseWidth;

		ellipseWidth *= 0.5;
		ellipseHeight *= 0.5;

		if (ellipseWidth > width / 2) ellipseWidth = width / 2;
		if (ellipseHeight > height / 2) ellipseHeight = height / 2;
		if (scale9Grid != null)
		{
			var scaledLeft = toScale9Position(s, x, scale9Grid.x, scale9Grid.width, scale9UnscaledWidth, scaleX);
			var scaledTop = toScale9Position(s, y, scale9Grid.y, scale9Grid.height, scale9UnscaledHeight, scaleY);
			var scaledRight = toScale9Position(s, x + width, scale9Grid.x, scale9Grid.width, scale9UnscaledWidth, scaleX);
			var scaledBottom = toScale9Position(s, y + height, scale9Grid.y, scale9Grid.height, scale9UnscaledHeight, scaleY);

			if ((s.fillScale9Bounds != null && s.bitmapFill != null) || (s.strokeScale9Bounds != null && s.bitmapStroke != null))
			{
				applyScale9GridUnscaledX(s, x);
				applyScale9GridUnscaledY(s, y);
				applyScale9GridUnscaledX(s, x + width);
				applyScale9GridUnscaledY(s, y + height);
				applyScale9GridScaledX(s, scaledLeft);
				applyScale9GridScaledY(s, scaledTop);
				applyScale9GridScaledX(s, scaledRight);
				applyScale9GridScaledY(s, scaledBottom);
			}

			var scaledLeftX = toScale9Position(s, x + ellipseWidth, scale9Grid.x, scale9Grid.width, scale9UnscaledWidth, scaleX);
			var scaledTopY = toScale9Position(s, y + ellipseHeight, scale9Grid.y, scale9Grid.height, scale9UnscaledHeight, scaleY);

			var scaledRightX = toScale9Position(s, x + width - ellipseWidth, scale9Grid.x, scale9Grid.width, scale9UnscaledWidth, scaleX);
			var scaledBottomY = toScale9Position(s, y + height - ellipseHeight, scale9Grid.y, scale9Grid.height, scale9UnscaledHeight, scaleY);

			s.cairo.moveTo(scaledLeftX, scaledTop);
			s.cairo.lineTo(scaledRightX, scaledTop);
			quadraticCurveTo(s, scaledRight, scaledTop, scaledRight, scaledTopY);
			s.cairo.lineTo(scaledRight, scaledBottomY);
			quadraticCurveTo(s, scaledRight, scaledBottom, scaledRightX, scaledBottom);
			s.cairo.lineTo(scaledLeftX, scaledBottom);
			quadraticCurveTo(s, scaledLeft, scaledBottom, scaledLeft, scaledBottomY);
			s.cairo.lineTo(scaledLeft, scaledTopY);
			quadraticCurveTo(s, scaledLeft, scaledTop, scaledLeftX, scaledTop);
		}
		else
		{
			var xe = x + width,
				ye = y + height,
				cx1 = -ellipseWidth + (ellipseWidth * SIN45),
				cx2 = -ellipseWidth + (ellipseWidth * TAN22),
				cy1 = -ellipseHeight + (ellipseHeight * SIN45),
				cy2 = -ellipseHeight + (ellipseHeight * TAN22);

			s.cairo.moveTo(xe, ye - ellipseHeight);
			quadraticCurveTo(s, xe, ye + cy2, xe + cx1, ye + cy1);
			quadraticCurveTo(s, xe + cx2, ye, xe - ellipseWidth, ye);
			s.cairo.lineTo(x + ellipseWidth, ye);
			quadraticCurveTo(s, x - cx2, ye, x - cx1, ye + cy1);
			quadraticCurveTo(s, x, ye + cy2, x, ye - ellipseHeight);
			s.cairo.lineTo(x, y + ellipseHeight);
			quadraticCurveTo(s, x, y - cy2, x - cx1, y - cy1);
			quadraticCurveTo(s, x - cx2, y, x + ellipseWidth, y);
			s.cairo.lineTo(xe - ellipseWidth, y);
			quadraticCurveTo(s, xe + cx2, y, xe + cx1, y - cy1);
			quadraticCurveTo(s, xe, y - cy2, xe, y + ellipseHeight);
			s.cairo.lineTo(xe, ye - ellipseHeight);
		}
	}

	private static function endFill(s:CairoGraphicsState):Void
	{
		s.cairo.newPath();
		playCommands(s, s.fillCommands, false);
		s.fillCommands.clear();
	}

	private static function endStroke(s:CairoGraphicsState):Void
	{
		s.cairo.newPath();
		playCommands(s, s.strokeCommands, true);
		s.cairo.closePath();
		s.strokeCommands.clear();
	}

	private static function toScale9Position(s:CairoGraphicsState, pos:Float, scale9Start:Float, scale9Center:Float, unscaledSize:Float, scale:Float):Float
	{
		if (scale <= 0.0)
		{
			// doesn't render if scaled with negative value
			return 0.0;
		}
		var scale9End = unscaledSize - scale9Center - scale9Start;
		var size = unscaledSize * scale;
		var center = size - scale9Start - scale9End;
		if (pos <= scale9Start)
		{
			// start region
			if (center < 0.0)
			{
				return pos * (scale9Start + scale9End + center) / (scale9Start + scale9End);
			}
			return pos;
		}
		if (pos >= (scale9Start + scale9Center))
		{
			// end region
			if (center < 0.0)
			{
				return (scale9Start + (pos - scale9Start - scale9Center)) * (scale9Start + scale9End + center) / (scale9Start + scale9End);
			}
			return scale9Start + center + (pos - scale9Start - scale9Center);
		}
		// center region
		if (center < 0.0)
		{
			return scale9Start * (scale9Start + scale9End + center) / (scale9Start + scale9End);
		}
		return scale9Start + center * (pos - scale9Start) / scale9Center;
	}

	private static function applyScale9GridUnscaledX(s:CairoGraphicsState, x:Float):Void
	{
		if (s.fillScale9Bounds != null && s.bitmapFill != null)
		{
			s.fillScale9Bounds.applyUnscaledX(x);
		}
		if (s.strokeScale9Bounds != null && s.bitmapStroke != null)
		{
			s.strokeScale9Bounds.applyUnscaledX(x);
		}
	}

	private static function applyScale9GridUnscaledY(s:CairoGraphicsState, y:Float):Void
	{
		if (s.fillScale9Bounds != null && s.bitmapFill != null)
		{
			s.fillScale9Bounds.applyUnscaledY(y);
		}
		if (s.strokeScale9Bounds != null && s.bitmapStroke != null)
		{
			s.strokeScale9Bounds.applyUnscaledY(y);
		}
	}

	private static function applyScale9GridScaledX(s:CairoGraphicsState, x:Float):Void
	{
		if (s.fillScale9Bounds != null && s.bitmapFill != null)
		{
			s.fillScale9Bounds.applyScaledX(x);
		}
		if (s.strokeScale9Bounds != null && s.bitmapStroke != null)
		{
			s.strokeScale9Bounds.applyScaledX(x);
		}
	}

	private static function applyScale9GridScaledY(s:CairoGraphicsState, y:Float):Void
	{
		if (s.fillScale9Bounds != null && s.bitmapFill != null)
		{
			s.fillScale9Bounds.applyScaledY(y);
		}
		if (s.strokeScale9Bounds != null && s.bitmapStroke != null)
		{
			s.strokeScale9Bounds.applyScaledY(y);
		}
	}
	#end

	public static function hitTest(s:CairoGraphicsState, graphics:Graphics, x:Float, y:Float):Bool
	{
		#if lime_cairo
		s.graphics = graphics;
		s.bounds = graphics.__bounds;

		if (graphics.__commands.length == 0 || s.bounds == null || s.bounds.width == 0 || s.bounds.height == 0 || !s.bounds.contains(x, y))
		{
			s.graphics = null;
			return false;
		}
		else
		{
			s.hitTesting = true;

			x -= s.bounds.x;
			y -= s.bounds.y;

			if (graphics.__cairo == null)
			{
				var bitmap = new BitmapData(Math.floor(Math.max(1, s.bounds.width)), Math.floor(Math.max(1, s.bounds.height)), true, 0);
				var surface = bitmap.getSurface();
				graphics.__cairo = new Cairo(surface);
				// graphics.__bitmap = bitmap;
			}

			s.cairo = graphics.__cairo;

			s.fillCommands.clear();
			s.strokeCommands.clear();

			s.hasFill = false;
			s.hasStroke = false;

			s.fillPattern = null;
			s.strokePattern = null;

			s.cairo.newPath();
			s.cairo.fillRule = EVEN_ODD;

			var data = new DrawCommandReader(graphics.__commands);

			for (type in graphics.__commands.types)
			{
				switch (type)
				{
					case CUBIC_CURVE_TO:
						var c = data.readCubicCurveTo();
						s.fillCommands.cubicCurveTo(c.controlX1, c.controlY1, c.controlX2, c.controlY2, c.anchorX, c.anchorY);
						s.strokeCommands.cubicCurveTo(c.controlX1, c.controlY1, c.controlX2, c.controlY2, c.anchorX, c.anchorY);

					case CURVE_TO:
						var c = data.readCurveTo();
						s.fillCommands.curveTo(c.controlX, c.controlY, c.anchorX, c.anchorY);
						s.strokeCommands.curveTo(c.controlX, c.controlY, c.anchorX, c.anchorY);

					case LINE_TO:
						var c = data.readLineTo();
						s.fillCommands.lineTo(c.x, c.y);
						s.strokeCommands.lineTo(c.x, c.y);

					case MOVE_TO:
						var c = data.readMoveTo();
						s.fillCommands.moveTo(c.x, c.y);
						s.strokeCommands.moveTo(c.x, c.y);

					case LINE_STYLE:
						endStroke(s);

						if (s.hasStroke && s.cairo.inStroke(x, y))
						{
							data.destroy();
							s.graphics = null;
							return true;
						}

						var c = data.readLineStyle();
						s.strokeCommands.lineStyle(c.thickness, c.color, 1, c.pixelHinting, c.scaleMode, c.caps, c.joints, c.miterLimit);

					case LINE_GRADIENT_STYLE:
						var c = data.readLineGradientStyle();
						s.strokeCommands.lineGradientStyle(c.type, c.colors, c.alphas, c.ratios, c.matrix, c.spreadMethod, c.interpolationMethod,
							c.focalPointRatio);

					case LINE_BITMAP_STYLE:
						var c = data.readLineBitmapStyle();
						s.strokeCommands.lineBitmapStyle(c.bitmap, c.matrix, c.repeat, c.smooth);

					case END_FILL:
						data.readEndFill();
						endFill(s);

						if (s.hasFill && s.cairo.inFill(x, y))
						{
							data.destroy();
							s.graphics = null;
							return true;
						}

						endStroke(s);

						if (s.hasStroke && s.cairo.inStroke(x, y))
						{
							data.destroy();
							s.graphics = null;
							return true;
						}

						s.hasFill = false;
						s.bitmapFill = null;
						s.bitmapFillMatrix = null;

					case BEGIN_BITMAP_FILL, BEGIN_FILL, BEGIN_GRADIENT_FILL, BEGIN_SHADER_FILL:
						endFill(s);

						if (s.hasFill && s.cairo.inFill(x, y))
						{
							data.destroy();
							s.graphics = null;
							return true;
						}

						endStroke(s);

						if (s.hasStroke && s.cairo.inStroke(x, y))
						{
							data.destroy();
							s.graphics = null;
							return true;
						}

						if (type == BEGIN_BITMAP_FILL)
						{
							var c = data.readBeginBitmapFill();
							s.fillCommands.beginBitmapFill(c.bitmap, c.matrix, c.repeat, c.smooth);
							s.strokeCommands.beginBitmapFill(c.bitmap, c.matrix, c.repeat, c.smooth);
						}
						else if (type == BEGIN_GRADIENT_FILL)
						{
							var c = data.readBeginGradientFill();
							s.fillCommands.beginGradientFill(c.type, c.colors, c.alphas, c.ratios, c.matrix, c.spreadMethod, c.interpolationMethod,
								c.focalPointRatio);
							s.strokeCommands.beginGradientFill(c.type, c.colors, c.alphas, c.ratios, c.matrix, c.spreadMethod, c.interpolationMethod,
								c.focalPointRatio);
						}
						else if (type == BEGIN_SHADER_FILL)
						{
							var c = data.readBeginShaderFill();
							s.fillCommands.beginShaderFill(c.shaderBuffer);
							s.strokeCommands.beginShaderFill(c.shaderBuffer);
						}
						else
						{
							var c = data.readBeginFill();
							s.fillCommands.beginFill(c.color, 1);
							s.strokeCommands.beginFill(c.color, 1);
						}

					case DRAW_CIRCLE:
						var c = data.readDrawCircle();
						s.fillCommands.drawCircle(c.x, c.y, c.radius);
						s.strokeCommands.drawCircle(c.x, c.y, c.radius);

					case DRAW_ELLIPSE:
						var c = data.readDrawEllipse();
						s.fillCommands.drawEllipse(c.x, c.y, c.width, c.height);
						s.strokeCommands.drawEllipse(c.x, c.y, c.width, c.height);

					case DRAW_RECT:
						var c = data.readDrawRect();
						s.fillCommands.drawRect(c.x, c.y, c.width, c.height);
						s.strokeCommands.drawRect(c.x, c.y, c.width, c.height);

					case DRAW_ROUND_RECT:
						var c = data.readDrawRoundRect();
						s.fillCommands.drawRoundRect(c.x, c.y, c.width, c.height, c.ellipseWidth, c.ellipseHeight);
						s.strokeCommands.drawRoundRect(c.x, c.y, c.width, c.height, c.ellipseWidth, c.ellipseHeight);

					case WINDING_EVEN_ODD:
						data.readWindingEvenOdd();
						s.cairo.fillRule = EVEN_ODD;

					case WINDING_NON_ZERO:
						data.readWindingNonZero();
						s.cairo.fillRule = WINDING;

					default:
						data.skip(type);
				}
			}

			var hitTest = false;

			if (s.fillCommands.length > 0)
			{
				endFill(s);
			}

			if (s.hasFill && s.cairo.inFill(x, y))
			{
				hitTest = true;
			}

			if (s.strokeCommands.length > 0)
			{
				endStroke(s);
			}

			if (s.hasStroke && s.cairo.inStroke(x, y))
			{
				hitTest = true;
			}

			data.destroy();

			s.graphics = null;
			return hitTest;
		}
		#end

		return false;
	}

	#if lime_cairo
	private static inline function isCCW(s:CairoGraphicsState, x1:Float, y1:Float, x2:Float, y2:Float, x3:Float, y3:Float):Bool
	{
		return ((x2 - x1) * (y3 - y1) - (y2 - y1) * (x3 - x1)) < 0;
	}

	private static function normalizeUVT(s:CairoGraphicsState, uvt:Vector<Float>, skipT:Bool = false):NormalizedUVT
	{
		var max:Float = Math.NEGATIVE_INFINITY;
		var tmp = Math.NEGATIVE_INFINITY;
		var len = uvt.length;

		for (t in 1...len + 1)
		{
			if (skipT && t % 3 == 0)
			{
				continue;
			}

			tmp = uvt[t - 1];

			if (max < tmp)
			{
				max = tmp;
			}
		}

		if (!skipT)
		{
			return {max: max, uvt: uvt};
		}

		var result = new Vector<Float>();

		for (t in 1...len + 1)
		{
			if (skipT && t % 3 == 0)
			{
				continue;
			}

			result.push(uvt[t - 1]);
		}

		return {max: max, uvt: result};
	}

	private static function playCommands(s:CairoGraphicsState, commands:DrawCommandBuffer, stroke:Bool = false):Void
	{
		if (commands.length == 0) return;

		s.bounds = s.graphics.__bounds;

		var offsetX = s.bounds.x;
		var offsetY = s.bounds.y;

		var positionX = 0.0;
		var positionY = 0.0;

		var closeGap = false;
		var startX = 0.0;
		var startY = 0.0;
		var setStart = false;

		s.cairo.fillRule = EVEN_ODD;
		s.cairo.antialias = SUBPIXEL;

		var hasPath:Bool = false;

		var scale9Grid:Rectangle = s.graphics.__owner.__scale9Grid;
		#if (openfl_legacy_scale9grid && !cairo)
		var hasScale9Grid:Bool = false;
		#else
		var hasScale9Grid = scale9Grid != null && !s.graphics.__owner.__isMask && s.graphics.__worldTransform.b == 0 && s.graphics.__worldTransform.c == 0;
		#end
		if (!hasScale9Grid)
		{
			scale9Grid = null;
			if (s.fillScale9Bounds != null)
			{
				s.fillScale9Bounds.clear();
			}
			if (s.strokeScale9Bounds != null)
			{
				s.strokeScale9Bounds.clear();
			}
		}

		var data = new DrawCommandReader(commands);

		var x:Float;
		var y:Float;
		var width:Float;
		var height:Float;
		var kappa = 0.5522848;
		var ox:Float;
		var oy:Float;
		var xe:Float;
		var ye:Float;
		var xm:Float;
		var ym:Float;
		var r:Float;
		var g:Float;
		var b:Float;

		for (type in commands.types)
		{
			switch (type)
			{
				case CUBIC_CURVE_TO:
					var c = data.readCubicCurveTo();
					hasPath = true;

					if (hasScale9Grid)
					{
						var scaledControlX1 = toScale9Position(s, c.controlX1, scale9Grid.x, scale9Grid.width, s.bounds.width, s.graphics.__owner.scaleX);
						var scaledControlY1 = toScale9Position(s, c.controlY1, scale9Grid.y, scale9Grid.height, s.bounds.height, s.graphics.__owner.scaleY);
						var scaledControlX2 = toScale9Position(s, c.controlX2, scale9Grid.x, scale9Grid.width, s.bounds.width, s.graphics.__owner.scaleX);
						var scaledControlY2 = toScale9Position(s, c.controlY2, scale9Grid.y, scale9Grid.height, s.bounds.height, s.graphics.__owner.scaleY);
						var scaledAnchorX = toScale9Position(s, c.anchorX, scale9Grid.x, scale9Grid.width, s.bounds.width, s.graphics.__owner.scaleX);
						var scaledAnchorY = toScale9Position(s, c.anchorY, scale9Grid.y, scale9Grid.height, s.bounds.height, s.graphics.__owner.scaleY);

						if ((s.fillScale9Bounds != null && s.bitmapFill != null) || (s.strokeScale9Bounds != null && s.bitmapStroke != null))
						{
							applyScale9GridUnscaledX(s, c.anchorX);
							applyScale9GridUnscaledY(s, c.anchorY);
							applyScale9GridScaledX(s, scaledAnchorX);
							applyScale9GridScaledY(s, scaledAnchorY);
						}

						s.cairo.curveTo(scaledControlX1
							- offsetX, scaledControlY1
							- offsetY, scaledControlX2
							- offsetX, scaledControlY2
							- offsetY,
							scaledAnchorX
							- offsetX, scaledAnchorY
							- offsetY);

						positionX = scaledAnchorX;
						positionY = scaledAnchorY;
					}
					else
					{
						s.cairo.curveTo(c.controlX1
							- offsetX, c.controlY1
							- offsetY, c.controlX2
							- offsetX, c.controlY2
							- offsetY, c.anchorX
							- offsetX,
							c.anchorY
							- offsetY);

						positionX = c.anchorX;
						positionY = c.anchorY;
					}

				case CURVE_TO:
					var c = data.readCurveTo();
					hasPath = true;

					if (hasScale9Grid)
					{
						var scaledControlX = toScale9Position(s, c.controlX, scale9Grid.x, scale9Grid.width, s.bounds.width, s.graphics.__owner.scaleX);
						var scaledControlY = toScale9Position(s, c.controlY, scale9Grid.y, scale9Grid.height, s.bounds.height, s.graphics.__owner.scaleY);
						var scaledAnchorX = toScale9Position(s, c.anchorX, scale9Grid.x, scale9Grid.width, s.bounds.width, s.graphics.__owner.scaleX);
						var scaledAnchorY = toScale9Position(s, c.anchorY, scale9Grid.y, scale9Grid.height, s.bounds.height, s.graphics.__owner.scaleY);

						if ((s.fillScale9Bounds != null && s.bitmapFill != null) || (s.strokeScale9Bounds != null && s.bitmapStroke != null))
						{
							applyScale9GridUnscaledX(s, c.anchorX);
							applyScale9GridUnscaledY(s, c.anchorY);
							applyScale9GridScaledX(s, scaledAnchorX);
							applyScale9GridScaledY(s, scaledAnchorY);
						}

						quadraticCurveTo(s, scaledControlX - offsetX, scaledControlY - offsetY, scaledAnchorX - offsetX, scaledAnchorY - offsetY);

						positionX = scaledAnchorX;
						positionY = scaledAnchorY;
					}
					else
					{
						quadraticCurveTo(s, c.controlX - offsetX, c.controlY - offsetY, c.anchorX - offsetX, c.anchorY - offsetY);

						positionX = c.anchorX;
						positionY = c.anchorY;
					}

				case DRAW_CIRCLE:
					var c = data.readDrawCircle();
					hasPath = true;

					if (hasScale9Grid)
					{
						var scaledLeft = toScale9Position(s, c.x - c.radius, scale9Grid.x, scale9Grid.width, s.bounds.width, s.graphics.__owner.scaleX);
						var scaledTop = toScale9Position(s, c.y - c.radius, scale9Grid.y, scale9Grid.height, s.bounds.height, s.graphics.__owner.scaleY);
						var scaledRight = toScale9Position(s, c.x + c.radius, scale9Grid.x, scale9Grid.width, s.bounds.width, s.graphics.__owner.scaleX);
						var scaledBottom = toScale9Position(s, c.y + c.radius, scale9Grid.y, scale9Grid.height, s.bounds.height, s.graphics.__owner.scaleY);

						if ((s.fillScale9Bounds != null && s.bitmapFill != null) || (s.strokeScale9Bounds != null && s.bitmapStroke != null))
						{
							applyScale9GridUnscaledX(s, c.x - c.radius);
							applyScale9GridUnscaledY(s, c.y - c.radius);
							applyScale9GridUnscaledX(s, c.x + c.radius);
							applyScale9GridUnscaledY(s, c.y + c.radius);
							applyScale9GridScaledX(s, scaledLeft);
							applyScale9GridScaledY(s, scaledTop);
							applyScale9GridScaledX(s, scaledRight);
							applyScale9GridScaledY(s, scaledBottom);
						}

						x = scaledLeft - offsetX;
						y = scaledTop - offsetY;
						width = scaledRight - scaledLeft;
						height = scaledBottom - scaledTop;

						if (width != 0.0 || height != 0.0)
						{
							ox = (width / 2) * kappa; // control point offset horizontal
							oy = (height / 2) * kappa; // control point offset vertical
							xe = x + width; // x-end
							ye = y + height; // y-end
							xm = x + width / 2; // x-middle
							ym = y + height / 2; // y-middle

							s.cairo.moveTo(x, ym);
							s.cairo.curveTo(x, ym - oy, xm - ox, y, xm, y);
							s.cairo.curveTo(xm + ox, y, xe, ym - oy, xe, ym);
							s.cairo.curveTo(xe, ym + oy, xm + ox, ye, xm, ye);
							s.cairo.curveTo(xm - ox, ye, x, ym + oy, x, ym);
						}
					}
					else if (c.radius != 0.0)
					{
						// flash doesn't draw the circle if the radius is zero
						s.cairo.moveTo(c.x - offsetX + c.radius, c.y - offsetY);
						s.cairo.arc(c.x - offsetX, c.y - offsetY, c.radius, 0, Math.PI * 2);
					}

				case DRAW_ELLIPSE:
					var c = data.readDrawEllipse();
					hasPath = true;

					if (hasScale9Grid)
					{
						// TODO: this is not how Flash behaves!
						// Flash seems to use multiple curves instead
						var scaledLeft = toScale9Position(s, c.x, scale9Grid.x, scale9Grid.width, s.bounds.width, s.graphics.__owner.scaleX);
						var scaledTop = toScale9Position(s, c.y, scale9Grid.y, scale9Grid.height, s.bounds.height, s.graphics.__owner.scaleY);
						var scaledRight = toScale9Position(s, c.x + c.width, scale9Grid.x, scale9Grid.width, s.bounds.width, s.graphics.__owner.scaleX);
						var scaledBottom = toScale9Position(s, c.y + c.height, scale9Grid.y, scale9Grid.height, s.bounds.height, s.graphics.__owner.scaleY);

						if ((s.fillScale9Bounds != null && s.bitmapFill != null) || (s.strokeScale9Bounds != null && s.bitmapStroke != null))
						{
							applyScale9GridUnscaledX(s, c.x);
							applyScale9GridUnscaledY(s, c.y);
							applyScale9GridUnscaledX(s, c.x + c.width);
							applyScale9GridUnscaledY(s, c.y + c.height);
							applyScale9GridScaledX(s, scaledLeft);
							applyScale9GridScaledY(s, scaledTop);
							applyScale9GridScaledX(s, scaledRight);
							applyScale9GridScaledY(s, scaledBottom);
						}

						x = scaledLeft;
						y = scaledTop;
						width = scaledRight - scaledLeft;
						height = scaledBottom - scaledTop;
					}
					else
					{
						x = c.x;
						y = c.y;
						width = c.width;
						height = c.height;
					}

					if (width != 0.0 || height != 0.0)
					{
						// flash doesn't draw the ellipse if both the width and
						// height are zero
						x -= offsetX;
						y -= offsetY;

						ox = (width / 2) * kappa; // control point offset horizontal
						oy = (height / 2) * kappa; // control point offset vertical
						xe = x + width; // x-end
						ye = y + height; // y-end
						xm = x + width / 2; // x-middle
						ym = y + height / 2; // y-middle

						s.cairo.moveTo(x, ym);
						s.cairo.curveTo(x, ym - oy, xm - ox, y, xm, y);
						s.cairo.curveTo(xm + ox, y, xe, ym - oy, xe, ym);
						s.cairo.curveTo(xe, ym + oy, xm + ox, ye, xm, ye);
						s.cairo.curveTo(xm - ox, ye, x, ym + oy, x, ym);
					}

				case DRAW_ROUND_RECT:
					var c = data.readDrawRoundRect();
					hasPath = true;
					drawRoundRect(s, c.x - offsetX, c.y - offsetY, c.width, c.height, c.ellipseWidth, c.ellipseHeight, scale9Grid, s.bounds.width, s.bounds.height,
						s.graphics.__owner.scaleX, s.graphics.__owner.scaleY);

				case LINE_TO:
					var c = data.readLineTo();
					hasPath = true;

					if (hasScale9Grid)
					{
						var scaledX = toScale9Position(s, c.x, scale9Grid.x, scale9Grid.width, s.bounds.width, s.graphics.__owner.scaleX);
						var scaledY = toScale9Position(s, c.y, scale9Grid.y, scale9Grid.height, s.bounds.height, s.graphics.__owner.scaleY);

						if ((s.fillScale9Bounds != null && s.bitmapFill != null) || (s.strokeScale9Bounds != null && s.bitmapStroke != null))
						{
							applyScale9GridUnscaledX(s, c.x);
							applyScale9GridUnscaledY(s, c.y);
							applyScale9GridScaledX(s, scaledX);
							applyScale9GridScaledY(s, scaledY);
						}

						if (positionX != scaledX || positionY != scaledY)
						{
							s.cairo.lineTo(scaledX - offsetX, scaledY - offsetY);
						}

						positionX = scaledX;
						positionY = scaledY;
					}
					else
					{
						if (positionX != c.x || positionY != c.y)
						{
							// flash doesn't draw the line if the previous
							// position is equal to the new position
							s.cairo.lineTo(c.x - offsetX, c.y - offsetY);
						}

						positionX = c.x;
						positionY = c.y;
					}

					if (positionX == startX && positionY == startY)
					{
						closeGap = true;
					}

				case MOVE_TO:
					var c = data.readMoveTo();

					if (hasScale9Grid)
					{
						var scaledX = toScale9Position(s, c.x, scale9Grid.x, scale9Grid.width, s.bounds.width, s.graphics.__owner.scaleX);
						var scaledY = toScale9Position(s, c.y, scale9Grid.y, scale9Grid.height, s.bounds.height, s.graphics.__owner.scaleY);

						if ((s.fillScale9Bounds != null && s.bitmapFill != null) || (s.strokeScale9Bounds != null && s.bitmapStroke != null))
						{
							applyScale9GridUnscaledX(s, c.x);
							applyScale9GridUnscaledY(s, c.y);
							applyScale9GridScaledX(s, scaledX);
							applyScale9GridScaledY(s, scaledY);
						}

						s.cairo.moveTo(scaledX - offsetX, scaledY - offsetY);

						positionX = scaledX;
						positionY = scaledY;
					}
					else
					{
						s.cairo.moveTo(c.x - offsetX, c.y - offsetY);

						positionX = c.x;
						positionY = c.y;
					}

					if (setStart && positionX != startX && positionY != startY)
					{
						closeGap = true;
					}

					startX = positionX;
					startY = positionY;
					setStart = true;

				case LINE_STYLE:
					var c = data.readLineStyle();
					if (stroke && s.hasStroke)
					{
						closePath(s, true);
					}

					s.cairo.moveTo(positionX - offsetX, positionY - offsetY);

					if (c.thickness == null)
					{
						s.hasStroke = false;
					}
					else
					{
						s.hasStroke = true;

						s.cairo.lineWidth = (c.thickness > 0 ? c.thickness : 1);

						if (c.joints == null)
						{
							s.cairo.lineJoin = ROUND;
						}
						else
						{
							s.cairo.lineJoin = switch (c.joints)
							{
								case MITER: MITER;
								case BEVEL: BEVEL;
								default: ROUND;
							}
						}

						if (c.caps == null)
						{
							s.cairo.lineCap = ROUND;
						}
						else
						{
							s.cairo.lineCap = switch (c.caps)
							{
								case NONE: BUTT;
								case SQUARE: SQUARE;
								default: ROUND;
							}
						}

						s.cairo.miterLimit = c.miterLimit;

						r = ((c.color & 0xFF0000) >>> 16) / 0xFF;
						g = ((c.color & 0x00FF00) >>> 8) / 0xFF;
						b = (c.color & 0x0000FF) / 0xFF;

						if (c.alpha == 1)
						{
							s.strokePattern = CairoPattern.createRGB(r, g, b);
						}
						else
						{
							s.strokePattern = CairoPattern.createRGBA(r, g, b, c.alpha);
						}
					}

					s.bitmapStroke = null;
					s.bitmapStrokeMatrix = null;

				case LINE_GRADIENT_STYLE:
					var c = data.readLineGradientStyle();
					if (stroke && s.hasStroke)
					{
						closePath(s, true);
					}

					s.cairo.moveTo(positionX - offsetX, positionY - offsetY);
					s.strokePattern = createGradientPattern(s, c.type, c.colors, c.alphas, c.ratios, c.matrix, c.spreadMethod, c.interpolationMethod,
						c.focalPointRatio);

					s.hasStroke = true;

					s.bitmapStroke = null;
					s.bitmapStrokeMatrix = null;

				case LINE_BITMAP_STYLE:
					var c = data.readLineBitmapStyle();
					if (stroke && s.hasStroke)
					{
						closePath(s, true);
					}

					s.cairo.moveTo(positionX - offsetX, positionY - offsetY);

					if (c.bitmap.readable)
					{
						s.strokePattern = createImagePattern(s, c.bitmap, c.repeat, c.smooth);
						s.bitmapStroke = c.bitmap;
						s.bitmapStrokeMatrix = c.matrix;
					}
					else
					{
						// if it's hardware-only BitmapData, fall back to
						// drawing solid black because we have no software
						// pixels to work with
						s.strokePattern = CairoPattern.createRGB(0, 0, 0);
						s.bitmapStroke = null;
						s.bitmapStrokeMatrix = null;
					}

					if (s.strokeScale9Bounds != null)
					{
						s.strokeScale9Bounds.clear();
					}
					else if (hasScale9Grid && s.bitmapStroke != null)
					{
						s.strokeScale9Bounds = new Scale9GridBounds();
					}

					s.hasStroke = true;

				case BEGIN_BITMAP_FILL:
					var c = data.readBeginBitmapFill();

					if (c.bitmap.readable)
					{
						s.fillPattern = createImagePattern(s, c.bitmap, c.repeat, c.smooth);
						s.bitmapFill = c.bitmap;
						s.bitmapFillMatrix = c.matrix;
					}
					else
					{
						// if it's hardware-only BitmapData, fall back to
						// drawing solid black because we have no software
						// pixels to work with
						s.fillPattern = CairoPattern.createRGB(0, 0, 0);
						s.bitmapFill = null;
						s.bitmapFillMatrix = null;
					}

					s.bitmapRepeat = c.repeat;

					s.hasFill = true;

					if (s.fillScale9Bounds != null)
					{
						s.fillScale9Bounds.clear();
					}
					else if (hasScale9Grid && s.bitmapFill != null)
					{
						s.fillScale9Bounds = new Scale9GridBounds();
					}

				case BEGIN_FILL:
					var c = data.readBeginFill();
					if (c.alpha < 0.005)
					{
						s.hasFill = false;
					}
					else
					{
						s.fillPattern = CairoPattern.createRGBA(((c.color & 0xFF0000) >>> 16) / 0xFF, ((c.color & 0x00FF00) >>> 8) / 0xFF,
							(c.color & 0x0000FF) / 0xFF, c.alpha);
						s.hasFill = true;
					}

					s.bitmapFill = null;
					s.bitmapFillMatrix = null;

					if (s.fillScale9Bounds != null)
					{
						s.fillScale9Bounds.clear();
					}

				case BEGIN_GRADIENT_FILL:
					var c = data.readBeginGradientFill();

					s.fillPattern = createGradientPattern(s, c.type, c.colors, c.alphas, c.ratios, c.matrix, c.spreadMethod, c.interpolationMethod,
						c.focalPointRatio);

					s.hasFill = true;
					s.bitmapFill = null;
					s.bitmapFillMatrix = null;

					if (s.fillScale9Bounds != null)
					{
						s.fillScale9Bounds.clear();
					}

				case BEGIN_SHADER_FILL:
					var c = data.readBeginShaderFill();
					var shaderBuffer = c.shaderBuffer;

					if (shaderBuffer.inputCount > 0)
					{
						s.bitmapFill = shaderBuffer.inputs[0];
						if (s.bitmapFill.readable)
						{
							s.fillPattern = createImagePattern(s, s.bitmapFill, shaderBuffer.inputWrap[0] != CLAMP, shaderBuffer.inputFilter[0] != NEAREST);
						}
						else
						{
							// if it's hardware-only BitmapData, fall back to
							// drawing solid black because we have no software
							// pixels to work with
							s.fillPattern = CairoPattern.createRGB(0, 0, 0);
						}
						s.hasFill = true;

						s.bitmapFillMatrix = null;
						s.bitmapRepeat = false;
					}

					if (s.fillScale9Bounds != null)
					{
						s.fillScale9Bounds.clear();
					}

				case DRAW_QUADS:
					var cacheExtend = s.fillPattern.extend;
					s.fillPattern.extend = CairoExtend.NONE;

					var c = data.readDrawQuads();
					var rects = c.rects;
					var indices = c.indices;
					var transforms = c.transforms;

					var hasIndices = (indices != null);
					var transformABCD = false, transformXY = false;

					var length = hasIndices ? indices.length : Math.floor(rects.length / 4);
					if (length == 0) return;

					if (transforms != null)
					{
						if (transforms.length >= length * 6)
						{
							transformABCD = true;
							transformXY = true;
						}
						else if (transforms.length >= length * 4)
						{
							transformABCD = true;
						}
						else if (transforms.length >= length * 2)
						{
							transformXY = true;
						}
					}

					var tileRect = Rectangle.__pool.get();
					var tileTransform = Matrix.__pool.get();

					var sourceRect = (s.bitmapFill != null) ? s.bitmapFill.rect : null;
					s.tempMatrix3.identity();

					var transform = s.graphics.__renderTransform;
					// var roundPixels = renderer.__roundPixels;
					var alpha = s.worldAlpha;

					var ri:Int;
					var ti:Int;

					for (i in 0...length)
					{
						ri = (hasIndices ? (indices[i] * 4) : i * 4);
						if (ri < 0) continue;

						// TODO: scale9Grid
						tileRect.setTo(rects[ri], rects[ri + 1], rects[ri + 2], rects[ri + 3]);

						if (tileRect.width <= 0 || tileRect.height <= 0)
						{
							continue;
						}

						if (transformABCD && transformXY)
						{
							ti = i * 6;
							tileTransform.setTo(transforms[ti], transforms[ti + 1], transforms[ti + 2], transforms[ti + 3], transforms[ti + 4],
								transforms[ti + 5]);
						}
						else if (transformABCD)
						{
							ti = i * 4;
							tileTransform.setTo(transforms[ti], transforms[ti + 1], transforms[ti + 2], transforms[ti + 3], tileRect.x, tileRect.y);
						}
						else if (transformXY)
						{
							ti = i * 2;
							tileTransform.tx = transforms[ti];
							tileTransform.ty = transforms[ti + 1];
						}
						else
						{
							tileTransform.tx = tileRect.x;
							tileTransform.ty = tileRect.y;
						}

						tileTransform.tx += positionX - offsetX;
						tileTransform.ty += positionY - offsetY;
						tileTransform.concat(transform);

						// if (roundPixels) {

						// 	tileTransform.tx = Math.round (tileTransform.tx);
						// 	tileTransform.ty = Math.round (tileTransform.ty);

						// }

						s.cairo.matrix = tileTransform.__toMatrix3();

						s.tempMatrix3.tx = tileRect.x;
						s.tempMatrix3.ty = tileRect.y;
						s.fillPattern.matrix = s.tempMatrix3;
						s.cairo.source = s.fillPattern;

						if (tileRect != sourceRect)
						{
							s.cairo.save();

							s.cairo.newPath();
							s.cairo.rectangle(0, 0, tileRect.width, tileRect.height);
							s.cairo.clip();
						}

						if (!s.hitTesting)
						{
							if (alpha == 1)
							{
								s.cairo.paint();
							}
							else
							{
								s.cairo.paintWithAlpha(alpha);
							}
						}

						if (tileRect != sourceRect)
						{
							s.cairo.restore();
						}
					}

					Rectangle.__pool.release(tileRect);
					Matrix.__pool.release(tileTransform);

					s.cairo.matrix = s.graphics.__renderTransform.__toMatrix3();
					s.fillPattern.extend = cacheExtend;

				case DRAW_TRIANGLES:
					var c = data.readDrawTriangles();
					var v = c.vertices;
					var ind = c.indices;
					var uvt = c.uvtData;
					var colorFill = s.bitmapFill == null;

					if (colorFill && uvt != null)
					{
						break;
					}

					var width = 0;
					var height = 0;
					var currentMatrix = s.graphics.__renderTransform.__toMatrix3();

					if (!colorFill && uvt != null)
					{
						var skipT = c.uvtData.length != v.length;
						var normalizedUVT = normalizeUVT(s, uvt, skipT);
						var maxUVT = normalizedUVT.max;
						uvt = normalizedUVT.uvt;

						if (maxUVT > 1)
						{
							width = Std.int(s.bounds.width);
							height = Std.int(s.bounds.height);
						}
						else
						{
							width = s.bitmapFill.width;
							height = s.bitmapFill.height;
						}
					}

					var i = 0;
					var l = ind.length;

					var a_:Int, b_:Int, c_:Int;
					var iax:Int, iay:Int, ibx:Int, iby:Int, icx:Int, icy:Int;
					var x1:Float, y1:Float, x2:Float, y2:Float, x3:Float, y3:Float;
					var uvx1:Float, uvy1:Float, uvx2:Float, uvy2:Float, uvx3:Float, uvy3:Float;
					var denom:Float;
					var t1:Float, t2:Float, t3:Float, t4:Float;
					var dx:Float, dy:Float;

					s.cairo.antialias = NONE;

					while (i < l)
					{
						a_ = i;
						b_ = i + 1;
						c_ = i + 2;

						iax = ind[a_] * 2;
						iay = ind[a_] * 2 + 1;
						ibx = ind[b_] * 2;
						iby = ind[b_] * 2 + 1;
						icx = ind[c_] * 2;
						icy = ind[c_] * 2 + 1;

						if (hasScale9Grid)
						{
							var scaledX1 = toScale9Position(s, v[iax], scale9Grid.x, scale9Grid.width, s.bounds.width, s.graphics.__owner.scaleX);
							var scaledY1 = toScale9Position(s, v[iay], scale9Grid.y, scale9Grid.height, s.bounds.height, s.graphics.__owner.scaleY);
							var scaledX2 = toScale9Position(s, v[ibx], scale9Grid.x, scale9Grid.width, s.bounds.width, s.graphics.__owner.scaleX);
							var scaledY2 = toScale9Position(s, v[iby], scale9Grid.y, scale9Grid.height, s.bounds.height, s.graphics.__owner.scaleY);
							var scaledX3 = toScale9Position(s, v[icx], scale9Grid.x, scale9Grid.width, s.bounds.width, s.graphics.__owner.scaleX);
							var scaledY3 = toScale9Position(s, v[icy], scale9Grid.y, scale9Grid.height, s.bounds.height, s.graphics.__owner.scaleY);

							if ((s.fillScale9Bounds != null && s.bitmapFill != null) || (s.strokeScale9Bounds != null && s.bitmapStroke != null))
							{
								applyScale9GridUnscaledX(s, v[iax]);
								applyScale9GridUnscaledY(s, v[iay]);
								applyScale9GridUnscaledX(s, v[ibx]);
								applyScale9GridUnscaledY(s, v[iby]);
								applyScale9GridUnscaledX(s, v[icx]);
								applyScale9GridUnscaledY(s, v[icy]);
								applyScale9GridScaledX(s, scaledX1);
								applyScale9GridScaledY(s, scaledY1);
								applyScale9GridScaledX(s, scaledX2);
								applyScale9GridScaledY(s, scaledY2);
								applyScale9GridScaledX(s, scaledX3);
								applyScale9GridScaledY(s, scaledY3);
							}

							x1 = scaledX1 - offsetX;
							y1 = scaledY1 - offsetY;
							x2 = scaledX2 - offsetX;
							y2 = scaledY2 - offsetY;
							x3 = scaledX3 - offsetX;
							y3 = scaledY3 - offsetY;
						}
						else
						{
							x1 = v[iax] - offsetX;
							y1 = v[iay] - offsetY;
							x2 = v[ibx] - offsetX;
							y2 = v[iby] - offsetY;
							x3 = v[icx] - offsetX;
							y3 = v[icy] - offsetY;
						}

						switch (c.culling)
						{
							case POSITIVE:
								if (!isCCW(s, x1, y1, x2, y2, x3, y3))
								{
									i += 3;
									continue;
								}

							case NEGATIVE:
								if (isCCW(s, x1, y1, x2, y2, x3, y3))
								{
									i += 3;
									continue;
								}

							default:
						}

						if (colorFill || uvt == null)
						{
							s.cairo.newPath();
							s.cairo.moveTo(x1, y1);
							s.cairo.lineTo(x2, y2);
							s.cairo.lineTo(x3, y3);
							s.cairo.closePath();

							var inverseTranslateX = 0.0;
							var inverseTranslateY = 0.0;
							var inverseScaleX = 1.0;
							var inverseScaleY = 1.0;
							if (!s.hitTesting && hasScale9Grid && s.fillScale9Bounds != null && s.bitmapFill != null)
							{
								var scaleX = s.fillScale9Bounds.getScaleX();
								var scaleY = s.fillScale9Bounds.getScaleY();

								if (scaleX > 0.0 && scaleY > 0.0)
								{
									s.cairo.scale(scaleX, scaleY);
									inverseScaleX = 1.0 / scaleX;
									inverseScaleY = 1.0 / scaleY;

									var remX = s.fillScale9Bounds.unscaledMinX % s.bitmapFill.width;
									var remY = s.fillScale9Bounds.unscaledMinY % s.bitmapFill.height;

									var adjustedRemX = (s.fillScale9Bounds.scale9MinX % (s.bitmapFill.width * scaleX)) / scaleX;
									var adjustedRemY = (s.fillScale9Bounds.scale9MinY % (s.bitmapFill.height * scaleY)) / scaleY;

									var translateX = adjustedRemX - remX;
									var translateY = adjustedRemY - remY;
									s.cairo.translate(translateX, translateY);
									inverseTranslateX = -translateX;
									inverseTranslateY = -translateY;
								}
							}

							s.cairo.source = s.fillPattern;
							if (!s.hitTesting) s.cairo.fillPreserve();

							if (!s.hitTesting && hasScale9Grid && s.fillScale9Bounds != null && s.bitmapFill != null)
							{
								s.cairo.translate(inverseTranslateX, inverseTranslateY);
								s.cairo.scale(inverseScaleX, inverseScaleY);
							}

							i += 3;
							continue;
						}

						s.cairo.matrix = s.graphics.__renderTransform.__toMatrix3();
						// cairo.identityMatrix();
						// cairo.resetClip();

						uvx1 = uvt[iax] * width;
						uvx2 = uvt[ibx] * width;
						uvx3 = uvt[icx] * width;
						uvy1 = uvt[iay] * height;
						uvy2 = uvt[iby] * height;
						uvy3 = uvt[icy] * height;

						denom = uvx1 * (uvy3 - uvy2) - uvx2 * uvy3 + uvx3 * uvy2 + (uvx2 - uvx3) * uvy1;

						if (denom == 0)
						{
							i += 3;
							continue;
						}

						s.cairo.newPath();
						s.cairo.moveTo(x1, y1);
						s.cairo.lineTo(x2, y2);
						s.cairo.lineTo(x3, y3);
						s.cairo.closePath();
						// cairo.clip ();

						x1 *= currentMatrix.a;
						x2 *= currentMatrix.a;
						x3 *= currentMatrix.a;
						y1 *= currentMatrix.d;
						y2 *= currentMatrix.d;
						y3 *= currentMatrix.d;

						t1 = -(uvy1 * (x3 - x2) - uvy2 * x3 + uvy3 * x2 + (uvy2 - uvy3) * x1) / denom;
						t2 = (uvy2 * y3 + uvy1 * (y2 - y3) - uvy3 * y2 + (uvy3 - uvy2) * y1) / denom;
						t3 = (uvx1 * (x3 - x2) - uvx2 * x3 + uvx3 * x2 + (uvx2 - uvx3) * x1) / denom;
						t4 = -(uvx2 * y3 + uvx1 * (y2 - y3) - uvx3 * y2 + (uvx3 - uvx2) * y1) / denom;
						dx = (uvx1 * (uvy3 * x2 - uvy2 * x3) + uvy1 * (uvx2 * x3 - uvx3 * x2) + (uvx3 * uvy2 - uvx2 * uvy3) * x1) / denom;
						dy = (uvx1 * (uvy3 * y2 - uvy2 * y3) + uvy1 * (uvx2 * y3 - uvx3 * y2) + (uvx3 * uvy2 - uvx2 * uvy3) * y1) / denom;

						s.tempMatrix3.setTo(t1, t2, t3, t4, dx, dy);
						s.cairo.matrix = s.tempMatrix3;
						s.cairo.source = s.fillPattern;
						if (!s.hitTesting) s.cairo.fill();

						i += 3;
					}

					s.cairo.matrix = s.graphics.__renderTransform.__toMatrix3();

				case DRAW_RECT:
					var c = data.readDrawRect();
					hasPath = true;

					if (hasScale9Grid)
					{
						var scaledLeft = toScale9Position(s, c.x, scale9Grid.x, scale9Grid.width, s.bounds.width, s.graphics.__owner.scaleX);
						var scaledTop = toScale9Position(s, c.y, scale9Grid.y, scale9Grid.height, s.bounds.height, s.graphics.__owner.scaleY);
						var scaledRight = toScale9Position(s, c.x + c.width, scale9Grid.x, scale9Grid.width, s.bounds.width, s.graphics.__owner.scaleX);
						var scaledBottom = toScale9Position(s, c.y + c.height, scale9Grid.y, scale9Grid.height, s.bounds.height, s.graphics.__owner.scaleY);

						if ((s.fillScale9Bounds != null && s.bitmapFill != null) || (s.strokeScale9Bounds != null && s.bitmapStroke != null))
						{
							applyScale9GridUnscaledX(s, c.x);
							applyScale9GridUnscaledY(s, c.y);
							applyScale9GridUnscaledX(s, c.x + c.width);
							applyScale9GridUnscaledY(s, c.y + c.height);
							applyScale9GridScaledX(s, scaledLeft);
							applyScale9GridScaledY(s, scaledTop);
							applyScale9GridScaledX(s, scaledRight);
							applyScale9GridScaledY(s, scaledBottom);
						}

						var scaledWidth = scaledRight - scaledLeft;
						var scaledHeight = scaledBottom - scaledTop;
						if (scaledWidth != 0.0 || scaledHeight != 0.0)
						{
							s.cairo.rectangle(scaledLeft - offsetX, scaledTop - offsetY, scaledWidth, scaledHeight);
						}
					}
					else if (c.width != 0.0 || c.height != 0.0)
					{
						// flash doesn't draw the rectangle if both the width
						// and height are zero
						s.cairo.rectangle(c.x - offsetX, c.y - offsetY, c.width, c.height);
					}

				case WINDING_EVEN_ODD:
					data.readWindingEvenOdd();
					s.cairo.fillRule = EVEN_ODD;

				case WINDING_NON_ZERO:
					data.readWindingNonZero();
					s.cairo.fillRule = WINDING;

				default:
					data.skip(type);
			}
		}

		data.destroy();

		if (hasPath)
		{
			if (stroke && s.hasStroke)
			{
				if (s.hasFill)
				{
					if (positionX != startX || positionY != startY)
					{
						s.cairo.lineTo(startX - offsetX, startY - offsetY);
						closeGap = true;
					}

					if (closeGap) closePath(s, true);
				}
				else if (closeGap && positionX == startX && positionY == startY)
				{
					closePath(s, true);
				}

				if (!s.hitTesting && (s.bitmapStrokeMatrix != null || (hasScale9Grid && s.strokeScale9Bounds != null && s.bitmapStroke != null)))
				{
					var matrix = Matrix.__pool.get();
					if (s.bitmapStrokeMatrix != null)
					{
						matrix.copyFrom(s.bitmapStrokeMatrix);
					}
					else
					{
						matrix.identity();
					}
					if (hasScale9Grid && s.strokeScale9Bounds != null && s.bitmapStroke != null)
					{
						var scaleX = s.strokeScale9Bounds.getScaleX();
						var scaleY = s.strokeScale9Bounds.getScaleY();
						if (scaleX > 0.0 && scaleY > 0.0)
						{
							matrix.scale(scaleX, scaleY);
						}
					}

					matrix.invert();
					s.strokePattern.matrix = matrix.__toMatrix3();
					Matrix.__pool.release(matrix);
				}

				s.cairo.source = s.strokePattern;
				if (!s.hitTesting) s.cairo.strokePreserve();
			}

			if (!stroke && s.hasFill)
			{
				s.cairo.translate(-s.bounds.x, -s.bounds.y);

				var inverseTranslateX = 0.0;
				var inverseTranslateY = 0.0;
				var inverseScaleX = 1.0;
				var inverseScaleY = 1.0;
				if (!s.hitTesting && hasScale9Grid && s.fillScale9Bounds != null && s.bitmapFill != null)
				{
					var scaleX = s.fillScale9Bounds.getScaleX();
					var scaleY = s.fillScale9Bounds.getScaleY();

					if (scaleX > 0.0 && scaleY > 0.0)
					{
						s.cairo.scale(scaleX, scaleY);
						inverseScaleX = 1.0 / scaleX;
						inverseScaleY = 1.0 / scaleY;

						var remX = s.fillScale9Bounds.unscaledMinX % s.bitmapFill.width;
						var remY = s.fillScale9Bounds.unscaledMinY % s.bitmapFill.height;

						var adjustedRemX = (s.fillScale9Bounds.scale9MinX % (s.bitmapFill.width * scaleX)) / scaleX;
						var adjustedRemY = (s.fillScale9Bounds.scale9MinY % (s.bitmapFill.height * scaleY)) / scaleY;

						var translateX = adjustedRemX - remX;
						var translateY = adjustedRemY - remY;
						s.cairo.translate(translateX, translateY);
						inverseTranslateX = -translateX;
						inverseTranslateY = -translateY;
					}
				}

				if (s.bitmapFillMatrix != null)
				{
					var matrix = Matrix.__pool.get();
					matrix.copyFrom(s.bitmapFillMatrix);
					matrix.invert();

					if (s.pendingMatrix != null)
					{
						matrix.concat(s.pendingMatrix);
					}

					s.fillPattern.matrix = matrix.__toMatrix3();

					Matrix.__pool.release(matrix);
				}

				s.cairo.source = s.fillPattern;

				if (s.pendingMatrix != null)
				{
					s.cairo.transform(s.pendingMatrix.__toMatrix3());
					if (!s.hitTesting) s.cairo.fillPreserve();
					s.cairo.transform(s.inversePendingMatrix.__toMatrix3());
				}
				else
				{
					if (!s.hitTesting) s.cairo.fillPreserve();
				}

				if (!s.hitTesting && hasScale9Grid && s.fillScale9Bounds != null && s.bitmapFill != null)
				{
					s.cairo.translate(inverseTranslateX, inverseTranslateY);
					s.cairo.scale(inverseScaleX, inverseScaleY);
				}

				s.cairo.translate(s.bounds.x, s.bounds.y);
				s.cairo.closePath();
			}
		}
	}

	private static function quadraticCurveTo(s:CairoGraphicsState, cx:Float, cy:Float, x:Float, y:Float):Void
	{
		var current:Vector2 = null;

		if (!s.cairo.hasCurrentPoint)
		{
			s.cairo.moveTo(cx, cy);
			current = new Vector2(cx, cy);
		}
		else
		{
			current = s.cairo.currentPoint;
		}

		var cx1 = current.x + ((2 / 3) * (cx - current.x));
		var cy1 = current.y + ((2 / 3) * (cy - current.y));
		var cx2 = x + ((2 / 3) * (cx - x));
		var cy2 = y + ((2 / 3) * (cy - y));

		s.cairo.curveTo(cx1, cy1, cx2, cy2, x, y);
	}
	#end

	public static function render(s:CairoGraphicsState, graphics:Graphics, renderer:CairoRenderer):Void
	{
		#if lime_cairo
		s.graphics = graphics;
		s.allowSmoothing = renderer.__allowSmoothing;
		s.worldAlpha = renderer.__getAlpha(graphics.__owner.__worldAlpha);

		#if (openfl_disable_hdpi || openfl_disable_hdpi_graphics)
		var pixelRatio = 1;
		#else
		var pixelRatio = renderer.__pixelRatio;
		#end

		graphics.__update(renderer.__worldTransform, pixelRatio);

		if (!graphics.__softwareDirty || graphics.__managed)
		{
			s.graphics = null;
			return;
		}

		s.bounds = graphics.__bounds;

		var scale9Grid:Rectangle = graphics.__owner.__scale9Grid;
		#if (openfl_legacy_scale9grid && !cairo)
		var hasScale9Grid:Bool = false;
		#else
		var hasScale9Grid = scale9Grid != null && !graphics.__owner.__isMask && graphics.__worldTransform.b == 0 && graphics.__worldTransform.c == 0;
		#end
		if (hasScale9Grid)
		{
			graphics.__bitmapScaleX = graphics.__owner.scaleX;
			graphics.__bitmapScaleY = graphics.__owner.scaleY;
		}
		else
		{
			graphics.__bitmapScaleX = 1;
			graphics.__bitmapScaleY = 1;
		}

		var width = graphics.__width;
		var height = graphics.__height;

		if (!graphics.__visible || graphics.__commands.length == 0 || s.bounds == null || width < 1 || height < 1)
		{
			graphics.__cairo = null;
			graphics.__bitmap = null;
		}
		else
		{
			s.hitTesting = false;

			if (graphics.__cairo != null)
			{
				var surface:CairoImageSurface = cast graphics.__cairo.target;

				// Surface must match __width x __height exactly. Context3DShape maps the
				// full bitmap dimensions to world coords via __worldTransform — if the
				// surface is oversized (from a previous high-scale render, or from the
				// legacy 1.25x upscaling margin), Cairo fills only the __width x __height
				// region and the empty padding visually clips content at the shape's
				// right/bottom edges.
				if (width != surface.width || height != surface.height)
				{
					graphics.__cairo = null;
				}
			}

			if (graphics.__cairo == null || graphics.__bitmap == null)
			{
				var bitmap = new BitmapData(width, height, true, 0);
				var surface = bitmap.getSurface();
				graphics.__cairo = new Cairo(surface);
				graphics.__bitmap = bitmap;
			}

			s.cairo = graphics.__cairo;

			renderer.__setBlendModeCairo(s.cairo, NORMAL);
			renderer.applyMatrix(graphics.__renderTransform, s.cairo);

			s.cairo.setOperator(CLEAR);
			s.cairo.paint();
			s.cairo.setOperator(OVER);

			s.fillCommands.clear();
			s.strokeCommands.clear();

			s.hasFill = false;
			s.hasStroke = false;

			s.fillPattern = null;
			s.strokePattern = null;

			var hasLineStyle = false;
			var initStrokeX = 0.0;
			var initStrokeY = 0.0;

			var data = new DrawCommandReader(graphics.__commands);

			for (type in graphics.__commands.types)
			{
				switch (type)
				{
					case CUBIC_CURVE_TO:
						var c = data.readCubicCurveTo();
						s.fillCommands.cubicCurveTo(c.controlX1, c.controlY1, c.controlX2, c.controlY2, c.anchorX, c.anchorY);

						if (hasLineStyle)
						{
							s.strokeCommands.cubicCurveTo(c.controlX1, c.controlY1, c.controlX2, c.controlY2, c.anchorX, c.anchorY);
						}
						else
						{
							initStrokeX = c.anchorX;
							initStrokeY = c.anchorY;
						}

					case CURVE_TO:
						var c = data.readCurveTo();
						s.fillCommands.curveTo(c.controlX, c.controlY, c.anchorX, c.anchorY);

						if (hasLineStyle)
						{
							s.strokeCommands.curveTo(c.controlX, c.controlY, c.anchorX, c.anchorY);
						}
						else
						{
							initStrokeX = c.anchorX;
							initStrokeY = c.anchorY;
						}

					case LINE_TO:
						var c = data.readLineTo();
						s.fillCommands.lineTo(c.x, c.y);

						if (hasLineStyle)
						{
							s.strokeCommands.lineTo(c.x, c.y);
						}
						else
						{
							initStrokeX = c.x;
							initStrokeY = c.y;
						}

					case MOVE_TO:
						var c = data.readMoveTo();
						s.fillCommands.moveTo(c.x, c.y);

						if (hasLineStyle)
						{
							s.strokeCommands.moveTo(c.x, c.y);
						}
						else
						{
							initStrokeX = c.x;
							initStrokeY = c.y;
						}

					case END_FILL:
						data.readEndFill();
						endFill(s);
						endStroke(s);
						s.hasFill = false;
						s.bitmapFill = null;
						s.bitmapFillMatrix = null;
						initStrokeX = 0;
						initStrokeY = 0;

					case LINE_GRADIENT_STYLE:
						var c = data.readLineGradientStyle();

						if (!hasLineStyle && (initStrokeX != 0 || initStrokeY != 0))
						{
							s.strokeCommands.moveTo(initStrokeX, initStrokeY);
							initStrokeX = 0;
							initStrokeY = 0;
						}

						hasLineStyle = true;
						s.strokeCommands.lineGradientStyle(c.type, c.colors, c.alphas, c.ratios, c.matrix, c.spreadMethod, c.interpolationMethod,
							c.focalPointRatio);

					case LINE_BITMAP_STYLE:
						var c = data.readLineBitmapStyle();

						if (!hasLineStyle && (initStrokeX != 0 || initStrokeY != 0))
						{
							s.strokeCommands.moveTo(initStrokeX, initStrokeY);
							initStrokeX = 0;
							initStrokeY = 0;
						}

						hasLineStyle = true;
						s.strokeCommands.lineBitmapStyle(c.bitmap, c.matrix, c.repeat, c.smooth);

					case LINE_STYLE:
						var c = data.readLineStyle();

						if (!hasLineStyle && c.thickness != null)
						{
							if (initStrokeX != 0 || initStrokeY != 0)
							{
								s.strokeCommands.moveTo(initStrokeX, initStrokeY);
								initStrokeX = 0;
								initStrokeY = 0;
							}
						}

						hasLineStyle = c.thickness != null;
						s.strokeCommands.lineStyle(c.thickness, c.color, c.alpha, c.pixelHinting, c.scaleMode, c.caps, c.joints, c.miterLimit);

					case BEGIN_BITMAP_FILL, BEGIN_FILL, BEGIN_GRADIENT_FILL, BEGIN_SHADER_FILL:
						endFill(s);
						endStroke(s);

						if (type == BEGIN_BITMAP_FILL)
						{
							var c = data.readBeginBitmapFill();
							s.fillCommands.beginBitmapFill(c.bitmap, c.matrix, c.repeat, c.smooth);
							s.strokeCommands.beginBitmapFill(c.bitmap, c.matrix, c.repeat, c.smooth);
						}
						else if (type == BEGIN_GRADIENT_FILL)
						{
							var c = data.readBeginGradientFill();
							s.fillCommands.beginGradientFill(c.type, c.colors, c.alphas, c.ratios, c.matrix, c.spreadMethod, c.interpolationMethod,
								c.focalPointRatio);
							s.strokeCommands.beginGradientFill(c.type, c.colors, c.alphas, c.ratios, c.matrix, c.spreadMethod, c.interpolationMethod,
								c.focalPointRatio);
						}
						else if (type == BEGIN_SHADER_FILL)
						{
							var c = data.readBeginShaderFill();
							s.fillCommands.beginShaderFill(c.shaderBuffer);
							s.strokeCommands.beginShaderFill(c.shaderBuffer);
						}
						else
						{
							var c = data.readBeginFill();
							s.fillCommands.beginFill(c.color, c.alpha);
							s.strokeCommands.beginFill(c.color, c.alpha);
						}

					case DRAW_CIRCLE:
						var c = data.readDrawCircle();
						s.fillCommands.drawCircle(c.x, c.y, c.radius);

						if (hasLineStyle)
						{
							s.strokeCommands.drawCircle(c.x, c.y, c.radius);
						}

					case DRAW_ELLIPSE:
						var c = data.readDrawEllipse();
						s.fillCommands.drawEllipse(c.x, c.y, c.width, c.height);

						if (hasLineStyle)
						{
							s.strokeCommands.drawEllipse(c.x, c.y, c.width, c.height);
						}

					case DRAW_RECT:
						var c = data.readDrawRect();
						s.fillCommands.drawRect(c.x, c.y, c.width, c.height);

						if (hasLineStyle)
						{
							s.strokeCommands.drawRect(c.x, c.y, c.width, c.height);
						}

					case DRAW_ROUND_RECT:
						var c = data.readDrawRoundRect();
						s.fillCommands.drawRoundRect(c.x, c.y, c.width, c.height, c.ellipseWidth, c.ellipseHeight);

						if (hasLineStyle)
						{
							s.strokeCommands.drawRoundRect(c.x, c.y, c.width, c.height, c.ellipseWidth, c.ellipseHeight);
						}

					case DRAW_QUADS:
						var c = data.readDrawQuads();
						s.fillCommands.drawQuads(c.rects, c.indices, c.transforms);

					case DRAW_TRIANGLES:
						var c = data.readDrawTriangles();
						s.fillCommands.drawTriangles(c.vertices, c.indices, c.uvtData, c.culling);

					case OVERRIDE_BLEND_MODE:
						var c = data.readOverrideBlendMode();
						renderer.__setBlendModeCairo(s.cairo, c.blendMode);

					case WINDING_EVEN_ODD:
						data.readWindingEvenOdd();
						s.fillCommands.windingEvenOdd();

					case WINDING_NON_ZERO:
						data.readWindingNonZero();
						s.fillCommands.windingNonZero();

					default:
						data.skip(type);
				}
			}

			if (s.fillCommands.length > 0)
			{
				endFill(s);
			}

			if (s.strokeCommands.length > 0)
			{
				endStroke(s);
			}

			data.destroy();

			graphics.__bitmap.image.dirty = true;
			graphics.__bitmap.image.version++;
		}

		graphics.__softwareDirty = false;
		graphics.__dirty = false;
		s.graphics = null;
		#end
	}

	public static function renderMask(s:CairoGraphicsState, graphics:Graphics, renderer:CairoRenderer):Void
	{
		#if lime_cairo
		if (graphics.__commands.length != 0)
		{
			s.cairo = renderer.cairo;

			var positionX = 0.0;
			var positionY = 0.0;

			var offsetX = 0;
			var offsetY = 0;

			var data = new DrawCommandReader(graphics.__commands);

			var x:Float;
			var y:Float;
			var width:Float;
			var height:Float;
			var kappa = 0.5522848;
			var ox:Float;
			var oy:Float;
			var xe:Float;
			var ye:Float;
			var xm:Float;
			var ym:Float;

			for (type in graphics.__commands.types)
			{
				switch (type)
				{
					case CUBIC_CURVE_TO:
						var c = data.readCubicCurveTo();
						s.cairo.curveTo(c.controlX1
							- offsetX, c.controlY1
							- offsetY, c.controlX2
							- offsetX, c.controlY2
							- offsetY, c.anchorX
							- offsetX,
							c.anchorY
							- offsetY);
						positionX = c.anchorX;
						positionY = c.anchorY;

					case CURVE_TO:
						var c = data.readCurveTo();
						quadraticCurveTo(s, c.controlX - offsetX, c.controlY - offsetY, c.anchorX - offsetX, c.anchorY - offsetY);
						positionX = c.anchorX;
						positionY = c.anchorY;

					case DRAW_CIRCLE:
						var c = data.readDrawCircle();
						s.cairo.arc(c.x - offsetX, c.y - offsetY, c.radius, 0, Math.PI * 2);

					case DRAW_ELLIPSE:
						var c = data.readDrawEllipse();

						x = c.x;
						y = c.y;
						width = c.width;
						height = c.height;

						x -= offsetX;
						y -= offsetY;

						ox = (width / 2) * kappa; // control point offset horizontal
						oy = (height / 2) * kappa; // control point offset vertical
						xe = x + width; // x-end
						ye = y + height; // y-end
						xm = x + width / 2; // x-middle
						ym = y + height / 2; // y-middle

						// closePath (false);
						// beginPath ();
						s.cairo.moveTo(x, ym);
						s.cairo.curveTo(x, ym - oy, xm - ox, y, xm, y);
						s.cairo.curveTo(xm + ox, y, xe, ym - oy, xe, ym);
						s.cairo.curveTo(xe, ym + oy, xm + ox, ye, xm, ye);
						s.cairo.curveTo(xm - ox, ye, x, ym + oy, x, ym);
					// closePath (false);

					case DRAW_RECT:
						var c = data.readDrawRect();
						s.cairo.rectangle(c.x - offsetX, c.y - offsetY, c.width, c.height);

					case DRAW_ROUND_RECT:
						var c = data.readDrawRoundRect();
						drawRoundRect(s, c.x - offsetX, c.y - offsetY, c.width, c.height, c.ellipseWidth, c.ellipseHeight);

					case LINE_TO:
						var c = data.readLineTo();
						s.cairo.lineTo(c.x - offsetX, c.y - offsetY);
						positionX = c.x;
						positionY = c.y;

					case MOVE_TO:
						var c = data.readMoveTo();
						s.cairo.moveTo(c.x - offsetX, c.y - offsetY);
						positionX = c.x;
						positionY = c.y;

					default:
						data.skip(type);
				}
			}

			data.destroy();
		}
		#end
	}
}

private typedef NormalizedUVT =
{
	max:Float,
	uvt:Vector<Float>
}

class Scale9GridBounds
{
	public var scale9MinX(default, null):Null<Float> = null;
	public var scale9MinY(default, null):Null<Float> = null;

	private var scale9MaxX:Null<Float> = null;
	private var scale9MaxY:Null<Float> = null;

	public var unscaledMinX(default, null):Null<Float> = null;
	public var unscaledMinY(default, null):Null<Float> = null;

	private var unscaledMaxX:Null<Float> = null;
	private var unscaledMaxY:Null<Float> = null;

	public function new() {}

	public function getScaleX():Float
	{
		if (scale9MaxX == null || unscaledMaxX == null)
		{
			return 1.0;
		}
		var unscaledWidth = unscaledMaxX - unscaledMinX;
		if (unscaledWidth == 0.0)
		{
			return 1.0;
		}
		return (scale9MaxX - scale9MinX) / unscaledWidth;
	}

	public function getScaleY():Float
	{
		if (scale9MaxY == null || unscaledMaxY == null)
		{
			return 1.0;
		}
		var unscaledHeight = unscaledMaxY - unscaledMinY;
		if (unscaledHeight == 0.0)
		{
			return 1.0;
		}
		return (scale9MaxY - scale9MinY) / unscaledHeight;
	}

	public function clear():Void
	{
		unscaledMinX = null;
		unscaledMaxX = null;
		unscaledMinY = null;
		unscaledMaxY = null;
		scale9MinX = null;
		scale9MaxX = null;
		scale9MinY = null;
		scale9MaxY = null;
	}

	public function applyUnscaledX(value:Float):Void
	{
		if (unscaledMinX == null || unscaledMinX > value)
		{
			unscaledMinX = value;
		}
		if (unscaledMaxX == null || unscaledMaxX < value)
		{
			unscaledMaxX = value;
		}
	}

	public function applyUnscaledY(value:Float):Void
	{
		if (unscaledMinY == null || unscaledMinY > value)
		{
			unscaledMinY = value;
		}
		if (unscaledMaxY == null || unscaledMaxY < value)
		{
			unscaledMaxY = value;
		}
	}

	public function applyScaledX(value:Float):Void
	{
		if (scale9MinX == null || scale9MinX > value)
		{
			scale9MinX = value;
		}
		if (scale9MaxX == null || scale9MaxX < value)
		{
			scale9MaxX = value;
		}
	}

	public function applyScaledY(value:Float):Void
	{
		if (scale9MinY == null || scale9MinY > value)
		{
			scale9MinY = value;
		}
		if (scale9MaxY == null || scale9MaxY < value)
		{
			scale9MaxY = value;
		}
	}
}
#end
