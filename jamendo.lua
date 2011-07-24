module('jamendo', package.seeall)

-- Grab environment
local os = os

-- Global variables
FORMAT_MP3 = { display = "MP3 (128k)", 
               short_display = "MP3", 
               value = "mp31" }
FORMAT_OGG = { display = "Ogg Vorbis (q4)", 
               short_display = "Ogg", 
               value = "ogg2" }
ORDER_RATINGDAILY = { display = "Daily rating", 
                      short_display = "daily rating", 
                      value = "ratingday_desc" }
ORDER_RATINGWEEKLY = { display = "Weekly rating", 
                      short_display = "weekly rating", 
                      value = "ratingweek_desc" }
ORDER_RATINGTOTAL = { display = "All time rating", 
                      short_display = "all time rating", 
                      value = "ratingtotal_desc" }
ORDER_RANDOM = { display = "Random", 
                 short_display = "random", 
                 value = "random_desc" }
SEARCH_ARTIST = { display = "Artist",
                  value = "artist" }
SEARCH_ALBUM = { display = "Album",
                 value = "album" }
SEARCH_TAG = { display = "Tag",
               value = "tag_idstr" }

current_request_table = { format = FORMAT_MP3,
                          order = ORDER_RATINGWEEKLY }

-- Local variables
local jamendo_list = {}
local cache_file = awful.util.getdir ("cache").."/jamendo_cache"
local default_mp3_stream = nil

-- Returns default stream number for MP3 format. Requests API for it
-- not more often than every hour.
function get_default_mp3_stream()
   if not default_mp3_stream or 
      (os.time() - default_mp3_stream.last_checked) > 3600 then
      local trygetlink = 
         assert(io.popen("echo $(curl -w %{redirect_url} " .. 
                         "'http://api.jamendo.com/get2/stream/track/redirect/" .. 
                         "?streamencoding="..format.."&id=729304')",'r')):read("*line")
      local _, _, prefix = string.find(trygetlink,"stream(%d+)\.jamendo\.com")
      default_mp3_stream = { id = prefix, last_checked = os.time() }
   end
   return default_mp3_stream.id
end

-- Returns the track ID from the given link to Jamendo stream.
function get_id_from_link(link)
   local _, _, id = string.find(link,"stream/(%d+)")
   return id
end

-- Returns link to music stream for the given track ID. Uses MP3
-- format and the default stream for it.
function get_link_by_id(id)
   return string.format("http://stream%s.jamendo.com/stream/%s/mp31/", 
                        get_default_mp3_stream(), id)
end

-- Returns track name for given music stream.
function get_name_by_link(link)
   return jamendo_list[get_id_from_link(link)]
end

-- Returns table of track IDs, names and other things based on the
-- request table.
function return_track_table(request_table)
   local req_string = form_request(request_table)
   local bus = assert(io.popen(req_string, 'r'))
   local response = bus:read("*all")
   bus:close()
   parse_table = parse_json(response)
   for i = 1, table.getn(parse_table) do
      if parse_table[i].stream == "" then
         -- Some songs don't have Ogg stream, use MP3 instead
         parse_table[i].stream = get_link_by_id(parse_table[i].id)
      end
      parse_table[i].display_name = 
         parse_table[i].artist_name .. " - " .. parse_table[i].name
      -- Save fetched tracks for further caching
      jamendo_list[parse_table[i].id] = parse_table[i].display_name
   end
   save_cache()
   return parse_table
end

-- Generates the request to Jamendo API based on provided request
-- table. If request_table is nil, uses current_request_table instead.
function form_request(request_table)
   local curl_str = 'echo $(curl -w %%{redirect_url} ' ..
      '"http://api.jamendo.com/get2/id+artist_name+name+stream/' ..
      'track/json/track_album+album_artist/?n=100&order=%s&streamencoding=%s")'
   if request_table then
      local format = request_table.format or current_request_table.format
      local order = request_table.order or current_request_table.order
      return string.format(curl_str, order.value, format.value)
   else
      print("Request : " .. string.format(curl_str, 
                           current_request_table.order.value,
                                        current_request_table.format.value))
      return string.format(curl_str, 
                           current_request_table.order.value,
                           current_request_table.format.value)
   end
end











-- Primitive function for parsing Jamendo API JSON response.  Does not
-- support arrays. Supports only strings and numbers as values.
-- Provides basic safety (correctly handles special symbols like comma
-- and curly brackets inside strings)
-- text - JSON text
function parse_json(text)
   local parse_table = {}
   local block = {}
   local i = 0
   local inblock = false
   local instring = false
   local curr_key = nil
   local curr_val = nil
   while i and i < string.len(text) do
      if not inblock then -- We are not inside the block, find next {
         i = string.find(text, "{", i+1)
         inblock = true
         block = {}
      else
         if not curr_key then -- We haven't found key yet
            if not instring then -- We are not in string, check for more tags
               local j = string.find(text, '"', i+1)
               local k = string.find(text, '}', i+1)
               if j and j < k then -- There are more tags in this block
                  i = j
                  instring = true
               else -- Block is over, find its ending
                  i = k
                  inblock = false
                  table.insert(parse_table, block)
               end
            else -- We are in string, find its ending
               _, i, curr_key = string.find(text,'(.-[^%\\])"', i+1)
               instring = false
            end
         else -- We have the key, let's find the value
            if not curr_val then -- Value is not found yet
               if not instring then -- Not in string, check if value is string
                  local j = string.find(text, '"', i+1)
                  local k = string.find(text, '[,}]', i+1)
                  if j and j < k then -- Value is string
                     i = j
                     instring = true
                  else -- Value is int
                     _, i, curr_val = string.find(text,'(%d+)', i+1)
                  end
               else -- We are in string, find its ending
                  local j = string.find(text, '"', i+1)
                  if j == i+1 then -- String is empty
                     i = j
                     curr_val = ""
                  else
                     _, i, curr_val = string.find(text,'(.-[^%\\])"', i+1)
                     curr_val = utf8_codes_to_symbols(curr_val)
                  end
                  instring = false
               end
            else -- We have both key and value, add it to table
               block[curr_key] = curr_val
               curr_key = nil
               curr_val = nil
            end
         end
      end
   end
   return parse_table
end

-- Jamendo returns Unicode symbols as \uXXXX. Lua does not transform
-- them into symbols so we need to do it ourselves.
function utf8_codes_to_symbols (s)
   local hexnums = "[%dabcdefABCDEF]"
   local pattern = string.format("\\u(%s%s%s%s?)", 
                                 hexnums, hexnums, hexnums, hexnums)
   local decode = function(code)
                     code = tonumber(code, 16)
                     -- Grab high and low byte
                     local hi = math.floor(code / 256) * 4 + 192
                     local lo = math.mod(code, 256)
                     -- Reduce low byte to 64, add overflow to high
                     local oflow = math.floor(lo / 64)
                     hi = hi + oflow
                     lo = math.mod(code, 64) + 128
                     -- Return symbol as \hi\lo
                     return string.char(hi, lo)
                  end
   return string.gsub(s, pattern, decode)
end

-- Retrieves mapping of track IDs to track names to avoid redundant
-- queries when Awesome gets restarted.
function retrieve_cache()
   local bus = io.open(cache_file)
   if bus then
      for l in bus:lines() do
         local _, _, id, track = string.find(l,"(%d+)-(.+)")
         jamendo_list[id] = track
      end
   end
end

-- Saves track IDs to track names mapping into the cache file.
function save_cache()
   local bus = io.open(cache_file, "w")
   for id,name in pairs(jamendo_list) do
      bus:write(id.."-"..name.."\n")
   end
   bus:flush()
   bus:close()
end

-- Retrieve cache on initialization
retrieve_cache()
