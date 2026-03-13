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
		// Boost pixelRatio by renderer's draw matrix (BitmapData.draw batchMatrix).
		// During normal screen rendering, __worldTransform is null → no boost.
		// Don't use textField.__worldTransform here — its scale changes on window
		// resize but the text cache isn't invalidated by pixelRatio change, causing
		// stale cache + new transform = mispositioned text.
		renderer.__softwareRenderer.__pixelRatio = rendererPixelRatio(renderer);

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
		renderer.__softwareRenderer.__pixelRatio = rendererPixelRatio(renderer);

		#if (js && html5)
		CanvasTextField.render(textField, cast renderer.__softwareRenderer, textField.__worldTransform);
		#elseif lime_cairo
		CairoTextField.render(textField, cast renderer.__softwareRenderer, textField.__worldTransform);
		#end
		textField.__graphics.__hardwareDirty = false;
	}

	/** Compute pixelRatio from renderer's draw matrix only (not display-tree transform). **/
	private static function rendererPixelRatio(renderer:OpenGLRenderer):Float
	{
		var pixelRatio = renderer.__pixelRatio;
		var rwt = renderer.__worldTransform;
		if (rwt != null)
		{
			var rsx = Math.sqrt(rwt.a * rwt.a + rwt.b * rwt.b);
			var rsy = Math.sqrt(rwt.c * rwt.c + rwt.d * rwt.d);
			var rs = Math.max(rsx, rsy);
			if (rs > pixelRatio) pixelRatio = rs;
		}
		return pixelRatio;
	}
}
#end
