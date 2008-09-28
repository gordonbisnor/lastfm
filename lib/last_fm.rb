require 'rexml/document'
require 'net/http'
require "digest"
require "uri"

# ActsAsLastFm
module LastFm
  
  # GET RAILS ENVIRONMENT (TEST, DEVELOPMENT, PRODUCTION)
  env = ENV['RAILS_ENV'] || RAILS_ENV

  # GET CONFIGURATION FILE FOR LAST FM
  config = YAML.load_file(RAILS_ROOT + '/config/last_fm.yml')[env]

  # SET API KEY CONSTANT
  Key = config['api_key']

  # SET SECRET (CURRENTLY NOT USING THIS FOR ANYTHING)
  Secret = config['secret']

  # PREFIX FOR LAST FM QUERIES
  Prefix = "/2.0/?api_key=#{Key}&method="

  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods

   # CALLED IN THE CONTROLLER TO MAKE INSTANCE METHODS AVAILABLE
    def last_fm
      include LastFm::InstanceMethods
    end    
    
  end # END CLASS METHODS MODULE

  # THESE INSTANE METHODS ARE AVAILABLE TO YOUR CONTROLLER
  module InstanceMethods

    # CLASS METHOD CALLED BY OTHER METHODS TO GET THE REQUIRED API SIGNATURE
    def get_signature(method,params)
      # EMPTY ARRAY
      signature = []
      # APPEND METHOD 
      signature << 'method' + method
      # APPEND EACH PARAM 
      params.each_pair do |key,value|
          signature << key.to_s + value
      end 
      # SORT ARRAY, THEN JOIN THEN APPEND THE SECRET FROM CONFIG
      signature = signature.sort.join + Secret
      # RETURN THE SIGNATURE, AN MD5 ENCRYPTION OF THE SORTED STRING
      return Digest::MD5.hexdigest(signature)
    end

    # PERFORM THE REST QUERY == THIS IS 'DEPRECATED'
    def fetch_last_fm(path)
      http = Net::HTTP.new("ws.audioscrobbler.com",80)
      path = url(path)
      resp, data = http.get(path)
       if resp.code == "200"
         return data
       else
         return false
       end	
    end

    # HELPER METHOD FOR URLs
    def url(string)
      return  string.gsub(/\ +/, '%20')
    end

    # THIS HELPER METHOD PROVIDES REDIRECT PATH TO THE LASTFM AUTH PAGE
    def authenticate_lastfm
      # redirect_to 
      "http://www.last.fm/api/auth/?api_key=#{Key}" 
    end # END AUTHENTICATE HELPER

    # CALLED BY YOUR CALLBACK URL METHOD TO REGISTER A SESSION
    def get_lastfm_session(token)
      signature = get_signature('auth.getsession',{:api_key=>Key,:token=>token}) 
      if
        @session = get_lastfm_with_auth('auth.getsession',{ :api_key => Key, :token => token, :signature => signature })
           session[:lastfm_name] = @session['session']['name']
           session[:lastfm_key] = @session['session']['key']
      else 
        return false
      end # END IF 
    end # END GET SESSION

    # PERFORM A REST QUERY WITHOUT AUTHORIZATION
    def get_lastfm(method,params,type='hash')
      http = Net::HTTP.new("ws.audioscrobbler.com",80)
      path = Prefix + method
      params.each_pair do |key,value|
        path << "&#{key}=#{value}"
      end # END EACH
      resp, data = http.get(url(path))
      if resp.code == "200"
        if type == 'hash'
          hash = Hash.from_xml(data)['lfm']
          hash.shift
          return hash
        else
          return data
        end # END IF TYPE
      else 
        return resp.body
      end # END IF RESP 200
      
    end # END GET

    # REST GET QUERY FOR AUTH REQUIRED METHODS
    # NEED TO PASS :sk=>session_key_we_fetched in the params 
    def get_lastfm_with_auth(method,params,type = 'hash')
      http = Net::HTTP.new("ws.audioscrobbler.com",80)
      path = Prefix + method
      # MAKE QUERY STRING FROM PARAMS
      params.each_pair do |key,value|
        path << "&#{key}=#{value}"
      end # END EACH
      # APPEND SIGNATURE TO QUERY STRING
      path << '&api_sig=' + get_signature(method,params)
      # MAKE THE CALL
      resp, data = http.get(url(path))
      # IF SUCCESS RETURN A HASH 
      if resp.code == "200"
        if type == 'hash'
          hash = Hash.from_xml(data)['lfm']
          hash.shift
          return hash
        else 
          return data
        end  # END IF TYPE
      # ELSE RETURN FALSE
      else 
        return false
      end # END IF RESP 200
    end # END GET WITH AUTH

    # AUTHORIZED POST TO LAST FM - CALL FROM YOUR METHOD THAT HAS RECEIVED THE POSTED FORM
    def post_lastfm(method,posted)
      # FIRST WE NEED TO ADD OUR KEY AND SESSION KEY TO THE HASH
      posted[:api_key] = Key
      posted[:sk] = session[:lastfm_key]
      # NOW WE CAN CALL THE GET SIGNATURE METHOD
      signature =  get_signature(method,posted)
      # WE CAN APPEND THE SIGNATURE
      posted[:api_sig] = get_signature(method,posted)
      # AND FINALLY THE METHOD
      posted[:method] = 'album.addTags'
      # DO THE POST
      resp = Net::HTTP.post_form(URI.parse('http://ws.audioscrobbler.com/2.0/'),posted)
      # HANDLE THE RESPONSE
      case resp
        # SUCCESS
        when Net::HTTPSuccess, Net::HTTPRedirection
          return true
        # FAILURE
        else
          return false
      end # END CASE
    end # END POST


# ---- SPECIFIC METHODS THAT PROVIDE PRE-FORMATTED HASHES ------------ #

     # ALBUM INFO - CALLING 1.0 SINCE V2 HAS NO TRACK LISTING
     # TO ADD?
    def lastfm_album_info(artist,album)
      # 2.0  path = "album.getinfo&artist=#{(artist)}&album=#{(album)}"
      path = "/1.0/album/#{artist}/#{album}/info.xml"
      data = fetch_last_fm(path)
      if not data == false
        xml = REXML::Document.new(data)	
        album = {}
        album['releasedate'] = xml.elements['releasedate'] ?xml.elements['releasedate'].text : ''
        album['url'] = xml.elements['url'] ? xml.elements['url'].text : ''
        coverart = xml.elements['//coverart']
        album['cover'] = coverart.elements['//large'] ? coverart.elements['//large'].text : ''
        tracks = []
        xml.elements.each('//track') do |el|
          tracks << { 
                  "title" => el.attributes["title"],
                  "url" =>   el.elements['url'] ? el.elements['url'].text : ''
                  }
        end # END EACH TRACK
        album['tracks'] = tracks
      end # END IF RESPONSE 200
      return album
    end # END ALBUM INFO METHOD

    def lastfm_artists_get_info(artist)
      path = "#{Prefix}artist.getinfo&artist=#{artist}"
      data = fetch_last_fm(path)
      if not data == false
        xml = REXML::Document.new(data)
        artist = {}
          artist['mbid'] = xml.elements['//mbid'] ?  xml.elements['//mbid'].text : ''
          artist['url'] = xml.elements['//url'] ? xml.elements['//url'].text : ''
        if not xml.elements['//bio'].nil?
          bio = xml.elements['//bio']
            artist['bio_summary'] = bio.elements['summary'] ? bio.elements['summary'].text : ''
            artist['bio_content'] = bio.elements['content'] ? bio.elements['content'].text : ''
        end
        artist['small_image'] =  xml.elements['//artist'].elements[4].text 
        artist['medium_image'] =  xml.elements['//artist'].elements[5].text 
        artist['large_image'] =  xml.elements['//artist'].elements[6].text 
      end # END IF DATA NOT FALSE
      return artist
    end


    # ARTISTS CURRENT EVENTS -- NOT EVEN CLOSE TO COMPLETE
    # TO ADD: eventid, artists headliner, venue location->street, postal, geo:point->geo:lat,geo:long,and loc timezone,startTime,desc,images...
    def lastfm_artists_current_events(artist, limit = 10)
      path = "#{Prefix}artist.getevents&artist=#{artist}"
      data = fetch_last_fm(path)
      if not data == false
        xml = REXML::Document.new(data)
        events = []
         i = 1
        # REFACTOR MY CODE METHOD
        xml.elements.each('//event') do |event| 
         if i <= limit
          bands = []
          artists = event.elements['artists']
          artists.elements.each('artist') do |band|
      	    bands << band.text   
          end # END EACH BAND
          venue = event.elements['venue']
          location = venue.elements['location']
          events << { 
                "title" => event.elements['title'].text, 
                "url" => event.elements['url'].text,  
                "date" => event.elements['startDate'].text, 
                "venue" => venue.elements['name'].text, 
                "city" => location.elements['city'].text, 
                "country" => location.elements['country'].text, 
                "venue_url" => venue.elements['url'].text,
                "bands" => bands 
                  }       
            end # if i
            i = i + 1
          end # END EACH EVENT
        end # END IF DATA NOT FALSE
        return events 
      end


    # ARTISTS SIMILAR ARTISTS -- COMPLETE
    def lastfm_similar_artists(artist,limit = 5)
      path = "#{Prefix}artist.similar&artist=#{artist}&limit=#{limit}"
      data = fetch_last_fm(path)
      if not data == false
        xml = REXML::Document.new(data)
        artists = []
        i = 1
        xml.elements.each('//artist') do |artist|
          if i <= limit
            artists << {
                  "name" => artist.elements['name'] ? artist.elements['name'].text : '',
                  "url" => artist.elements['url'] ? artist.elements['url'].text :  '' ,
                  "image" => artist.elements['image'] ? artist.elements['image'].text : '',
                  "small_image" => artist.elements['image'] ? artist.elements['image'].text : '',
                  "mbid" => artist.elements['mbid'] ? artist.elements['mbid'].text : '',
                  "match" => artist.elements['match'] ? artist.elements['match'].text : ''
                  }              
          end
          i = i + 1
        end
        return artists
      end
    end

    # WORKING - NEED TO MAP LARGE AND MEDIUM IMAGES BY ATTRIBUTE
    def lastfm_artists_top_albums(artist,limit = 5)          
      path = "#{Prefix}artist.topAlbums&artist=#{artist}"
      data = fetch_last_fm(path)
      if not data == false
        xml = REXML::Document.new(data)
        albums = []
        i = 1
        xml.elements.each('//album') do |album| 
          if i <= limit
            albums <<  { 
                  "name"=>album.elements['name'].text, 
                  "url" => album.elements['url'].text, 
                  "small_image" => album.elements['image'].text 
                  }
          end # if i
          i = i + 1
        end
      end
      return albums
    end

    # ARTISTS TOP TRACKS
    # TO ADD: rank attr, image small, medium, large
    #  mbid?, playcount, listens
    def lastfm_artists_top_tracks(artist, limit = 5)          
      path = "#{Prefix}artist.topTracks&artist=#{artist}"
      data = fetch_last_fm(path)
      if not data == false
        xml = REXML::Document.new(data)
        tracks = []
        i = 1
        xml.elements.each('//track') do |track| 
          if i <= limit
            tracks << {
                  "name"=>track.elements['name'].text,
                  "url"=>track.elements['url'].text
                  }
          end # if i
          i = i + 1
        end
      end
      return tracks
    end

    # ARTISTS TOP TAGS -- complete
    def lastfm_artists_top_tags(artist, limit = 10)
      path = "#{Prefix}artist.topTags&artist=#{artist}"
      data = fetch_last_fm(path)
      if not data == false
        xml = REXML::Document.new(data)
        tags = []
        i = 1
        xml.elements.each('//tag') do |tag|
          if i <= limit
            tags << { 'tag' => tag.elements['name'].text, 'url' => tag.elements['url'].text }              
          end # if i
          i = i + 1
        end
        return tags    
      end
    end

    # USERS WEEKLY ARTISTS
    # TO ADD:  from/to/user
    def lastfm_users_weekly_artists(user, limit = 10)
      path = "#{Prefix}user.getWeeklyArtistChart&user=#{user}"
      data = fetch_last_fm(path)
      if not data == false
        xml = REXML::Document.new(data)
        bands = []
        i = 1
        xml.elements.each('//artist') do |band| 
          if i <= limit
            bands << { 
                  "name" => band.elements['name'].text, 
                  "url" => band.elements['url'].text,
                  "mbid" => band.elements['mbid'].text,
                  "playcount" => band.elements['playcount'].text,
                  "rank" => band.attributes['rank']
                  }
          end # if i
          i = i + 1
        end
        return bands
      end
    end

    # USERS WEEKLY ALBUMS
    # ELEMENTS TO ADD: 
    #weekly album chart: user, from, to, 
    # could allow params of from and to
    def lastfm_users_weekly_albums(user, limit = 10)
      path = "#{Prefix}user.getWeeklyAlbumChart&user=#{user}"
      data = fetch_last_fm(path)
      if not data == false
        xml = REXML::Document.new(data)
        albums = []
        i = 1
        xml.elements.each('//album') do |album| 
          if i <= limit
            albums << { 
                  "name" => album.elements['name'].text,
                  "band" => album.elements['artist'].text,
                  "url" => album.elements['url'].text,
                  "album_mbid" => album.elements['mbid'].text,
                  "playcount" => album.elements['playcount'].text,
                  "artist_mbid" => album.elements['artist'].attributes['mbid'],
                  "rank" => album.attributes['rank']
                    }
          end # if i
          i = i + 1
        end
        return albums
      end
    end
 
 end # MODULE INSTANCE METHODS
 
end # END MODULE ACTS AS LAST FM