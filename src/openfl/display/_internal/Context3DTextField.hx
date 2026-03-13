package openfl.display._internal;

#if !flash
import openfl.display._internal.CairoTextField;
import openfl.display._internal.CanvasTextField;
import openfl.display.OpenGLRenderer;
import openfl.text.TextField;

#if !openfl_debug
@:fileXml(' tags="haxe,release" ')
@:noDebug
#end
@:access(openfl.display.Graphics)
@:access(openfl.text.TextField)
@SuppressWarnings("checkstyle:FieldDocComment")
class Context3DTextField
{
	public static function render(textField:TextField, renderer:OpenGLRenderer):Void
	{
		var wt = textField.__worldTransform;
		var sx = Math.sqrt(wt.a * wt.a + wt.b * wt.b);
		var sy = Math.sqrt(wt.c * wt.c + wt.d * wt.d);

		// Factor in renderer's draw matrix (e.g. BitmapData.draw batchMatrix).
		// textField.__worldTransform only has the local display-tree scale;
		// renderer.__worldTransform carries the additional draw-call scale.
		// On screen, renderer.__worldTransform is identity → no effect.
		var rwt = renderer.__worldTransform;
		if (rwt != null)
		{
			var rsx = Math.sqrt(rwt.a * rwt.a + rwt.b * rwt.b);
			var rsy = Math.sqrt(rwt.c * rwt.c + rwt.d * rwt.d);
			sx *= rsx;
			sy *= rsy;
		}

		renderer.__softwareRenderer.__pixelRatio = Math.max(renderer.__pixelRatio, Math.max(sx, sy));

		#if (js && html5)
		CanvasTextField.render(textField, cast renderer.__softwareRenderer, textField.__worldTransform);
		#elseif lime_cairo
		CairoTextField.render(textField, cast renderer.__softwareRenderer, textField.__worldTransform);
		#end
		textField.__graphics.__hardwareDirty = false;
	}

	public static function renderDrawable(textField:TextField, renderer:OpenGLRenderer):Void
	{
		renderer.__updateCacheBitmap(textField, false);

		if (textField.__cacheBitmap != null && !textField.__isCacheBitmapRender)
		{
			Context3DBitmap.render(textField.__cacheBitmap, renderer);
		}
		else
		{
			Context3DTextField.render(textField, renderer);
			Context3DDisplayObject.render(textField, renderer);
		}

		renderer.__renderEvent(textField);
	}

	public static function renderDrawableMask(textField:TextField, renderer:OpenGLRenderer):Void
	{
		Context3DTextField.renderMask(textField, renderer);
		Context3DDisplayObject.renderDrawableMask(textField, renderer);
	}

	public static function renderMask(textField:TextField, renderer:OpenGLRenderer):Void
	{
		var wt = textField.__worldTransform;
		var sx = Math.sqrt(wt.a * wt.a + wt.b * wt.b);
		var sy = Math.sqrt(wt.c * wt.c + wt.d * wt.d);

		var rwt = renderer.__worldTransform;
		if (rwt != null)
		{
			var rsx = Math.sqrt(rwt.a * rwt.a + rwt.b * rwt.b);
			var rsy = Math.sqrt(rwt.c * rwt.c + rwt.d * rwt.d);
			sx *= rsx;
			sy *= rsy;
		}

		renderer.__softwareRenderer.__pixelRatio = Math.max(renderer.__pixelRatio, Math.max(sx, sy));

		#if (js && html5)
		CanvasTextField.render(textField, cast renderer.__softwareRenderer, textField.__worldTransform);
		#elseif lime_cairo
		CairoTextField.render(textField, cast renderer.__softwareRenderer, textField.__worldTransform);
		#end
		textField.__graphics.__hardwareDirty = false;
	}
}
#end
