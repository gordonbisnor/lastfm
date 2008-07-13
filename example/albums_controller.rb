class AlbumsController < ApplicationController

  # MOVE TO APPLICATION CONTROLLER TO MAKE AVAILABLE TO ALL CONTROLLERS
  last_fm

  # FETCH AN ALBUM AND GET CURRENT EVENTS FOR THE BAND
  def show
    @album = Album.find(1)
    @current_events = lastfm_artists_current_events(@album.band.name)
  end

end