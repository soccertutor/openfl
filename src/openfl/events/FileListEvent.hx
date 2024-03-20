package openfl.events;

#if (!flash && sys && (!flash_doc_gen || air_doc_gen))
import openfl.events.Event;
import openfl.filesystem.File;

class FileListEvent extends Event
{
	public static inline var DIRECTORY_LISTING:EventType<FileListEvent> = "directoryListing";
	public static inline var SELECT_MULTIPLE:EventType<FileListEvent> = "selectMultiple";

	public var files:Array<File>;

	public function new(type:String, files:Array<File>, bubbles:Bool = false, cancelable:Bool = false)
	{
		super(type, bubbles, cancelable);
		this.files = files;
	}

	override public function clone():Event
	{
		return new FileListEvent(type, files, bubbles, cancelable);
	}
}
#else
#if air
typedef FileListEvent = flash.events.FileListEvent
#end
#end
