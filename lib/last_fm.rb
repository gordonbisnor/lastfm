require 'rexml/document'
require 'net/http'

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
   
    def last_fm
      include LastFm::InstanceMethods
    end    
  end

    # HELPER METHOD FOR URLs
    def url(string)
      return  string.gsub(/\ +/, '%20')
    end  

    # PERFORM THE REST QUERY
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

  module InstanceMethods

     # ALBUM INFO - CALLING 1.0 SINCE V2 HAS NO TRACK LISTING
    def lastfm_album_info(artist,album)
      # 2.0  path = "album.getinfo&artist=#{(artist)}&album=#{(album)}"
      path = "/1.0/album/#{artist}/#{album}/info.xml"
      data = fetch_last_fm(path)
      if not data == false
        xml = REXML::Document.new(data)	
        album = {}
        album['releasedate'] = xml.elements['releasedate']
        album['url'] = xml.elements['url']
        coverart = xml.elements['//coverart']
        album['cover'] = coverart.elements['//large'].text
        tracks = []
        xml.elements.each('//track') do |el|
          tracks << { 
                  "title" => el.attributes["title"],
                  "url" =>   el.elements['url'].text 
                  }
        end # END EACH TRACK
        album['tracks'] = tracks
      end # END IF RESPONSE 200
      return album
    end # END ALBUM INFO METHOD

    # ARTISTS CURRENT EVENTS
    def lastfm_artists_current_events(artist)
      path = "#{Prefix}artist.getevents&artist=#{artist}"
      data = fetch_last_fm(path)
      if not data == false
        xml = REXML::Document.new(data)
        events = []
        xml.elements.each('//event') do |event|
          bands = []
          artists = event.elements['artists']
          artists.elements.each('artist') do |band|
  	  bands << band.text   
          end
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
        end
        return events 
      end
    end

    # ARTISTS SIMILAR ARTISTS
    def lastfm_similar_artists(artist)
      path = "#{Prefix}artist.similar&artist=#{artist}"
      data = fetch_last_fm(path)
      if not data == false
        xml = REXML::Document.new(data)
        artists = []
        xml.elements.each('//artist') do |artist|
          artists << {
                  "name"=>artist.elements['name'].text,
                  "url"=>artist.elements['url'].text,
                  "image"=>artist.elements['image'].text,
                  "small_image"=>artist.elements['image_small'].text
                  }              
        end
        return artists
      end
    end

    # WORKING - NEED TO MAP LARGE AND MEDIUM IMAGES BY ATTRIBUTE
    def lastfm_artists_top_albums(artist)          
      path = "#{Prefix}artist.topAlbums&artist=#{artist}"
      data = fetch_last_fm(path)
      if not data == false
        xml = REXML::Document.new(data)
        albums = []
        xml.elements.each('//album') do |album|
          albums <<  { 
                  "name"=>album.elements['name'].text, 
                  "url" => album.elements['url'].text, 
                  "small_image" => album.elements['image'].text 
                  }
        end
      end
      return albums
    end

    # ARTISTS TOP TRACKS
    def lastfm_artists_top_tracks(artist)          
      path = "#{Prefix}artist.topTracks&artist=#{artist}"
      data = fetch_last_fm(path)
      if not data == false
        xml = REXML::Document.new(data)
        tracks = []
        xml.elements.each('//track') do |track|
          tracks << {
                  "name"=>track.elements['name'].text,
                  "url"=>track.elements['url'].text
                  }
        end
      end
      return tracks
    end

    # ARTISTS TOP TAGS
    def lastfm_artists_top_tags(artist)
      path = "#{Prefix}artist.topTags&artist=#{artist}"
      data = fetch_last_fm(path)
      if not data == false
        xml = REXML::Document.new(data)
        tags = []
        xml.elements.each('//tag') do |el|
          tags << { 
                  "tag" => el.elements['name'].text, 
                  "url" => el.elements["url"].text 
                  }
        end
        return tags    
      end
    end

    # USERS WEEKLY ARTISTS
    def lastfm_users_weekly_artists(user)
      path = "#{Prefix}user.getWeeklyArtistChart&user=#{user}"
      data = fetch_last_fm(path)
      if not data == false
        xml = REXML::Document.new(data)
        bands = []
        xml.elements.each('//artist') do |band|
          bands << { 
                  "name" => band.elements['name'].text, 
                  "url" => band.elements['url'].text 
                  }
        end
        return bands
      end
    end

    # USERS WEEKLY ALBUMS
    def lastfm_users_weekly_albums(user)
      path = "#{Prefix}user.getWeeklyAlbumChart&user=#{user}"
      data = fetch_last_fm(path)
      if not data == false
        xml = REXML::Document.new(data)
        albums = []
        xml.elements.each('//album') do |album|
          albums << { 
                  "name"=>album.elements['name'].text,
                  "band"=>album.elements['artist'].text,
                  "url"=>album.elements['url'].text 
                    }
        end
        return albums
      end
    end
 
 end # MODULE INSTANCE METHODS
 
end # END MODULE ACTS AS LAST FM