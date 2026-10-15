extends RefCounted

# Line-art icons for the command bar and sheet headers, drawn as small SVGs and rasterised
# once at three times their display size so they stay sharp on high-density phones. White
# strokes: buttons tint them through their icon colours.

const ART: Dictionary = {
	"build": "<path d='M3.5 11.5 12 4l8.5 7.5'/><path d='M6 10v10h12V10'/><path d='M10 20v-5h4v5'/><path d='M15.5 6.5V4h2v4.3'/>",
	"upgrade": "<path d='M12 4 5 11h4v9h6v-9h4z'/>",
	"horn": "<path d='M3 10.6v2.8c6 .2 10.6 2.6 15 6.4h2V4.2h-2C13.6 8 9 10.4 3 10.6z'/><path d='M8.5 10.2v3.6M13 8.4v7.2'/>",
	"more": "<path d='M7 3.5 10.5 7 7 10.5 3.5 7zM17 3.5 20.5 7 17 10.5 13.5 7zM7 13.5l3.5 3.5L7 20.5 3.5 17zM17 13.5l3.5 3.5-3.5 3.5-3.5-3.5z'/>",
	"collect": "<path d='M9 4.5h6l-1.8 3.3c4 1.6 6.3 5 5.8 8.6-.4 2.8-3 4.1-7 4.1s-6.6-1.3-7-4.1c-.5-3.6 1.8-7 5.8-8.6z'/><path d='M10.3 7.8h3.4'/><path d='M12 11.5v6M10 13.2c0-1 4-1 4 .2s-4 1.2-4 2.4 4 1 4 0'/>",
	"repair": "<path d='M13.5 3.5 20.5 10.5 18 13l-7-7z'/><path d='M14.5 9.5 4.5 19.5'/>",
	"zone": "<path d='M3.5 6.5 9 4.5l6 2 5.5-2v13l-5.5 2-6-2-5.5 2z'/><path d='M9 4.5v13M15 6.5v13'/>",
	"close": "<path d='M6 6l12 12M18 6 6 18'/>",
}

static var _cache: Dictionary = {}


static func texture(name: String, side: int = 26) -> Texture2D:
	var key: String = "%s@%d" % [name, side]
	if _cache.has(key):
		return _cache[key]
	if not ART.has(name):
		return null
	var svg: String = "<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24' fill='none' stroke='#ffffff' stroke-width='1.7' stroke-linecap='round' stroke-linejoin='round'>%s</svg>" % ART[name]
	var image := Image.new()
	if image.load_svg_from_string(svg, float(side * 3) / 24.0) != OK or image.is_empty():
		return null
	image.generate_mipmaps()
	var made := ImageTexture.create_from_image(image)
	_cache[key] = made
	return made
