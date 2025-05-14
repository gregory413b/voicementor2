import { useState, useRef, useEffect } from 'react';
import { Play, Pause, Bookmark, Star, Rewind, FastForward, MessageSquare } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { formatDuration } from '../../lib/utils';
import { useAuthStore } from '../../stores/authStore';

interface Bookmark {
  id: string;
  timestamp_sec: number;
  label: string;
}

interface AudioPlayerProps {
  messageId: string;
  audioUrl: string;
  duration: number;
  isFavorited?: boolean;
}

const AudioPlayer = ({ messageId, audioUrl, duration, isFavorited = false }: AudioPlayerProps) => {
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [favorite, setFavorite] = useState(isFavorited);
  const [audioSrc, setAudioSrc] = useState<string | null>(null);
  const [bookmarks, setBookmarks] = useState<Bookmark[]>([]);
  const [showBookmarks, setShowBookmarks] = useState(false);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const { user } = useAuthStore();
  
  useEffect(() => {
    const fetchAudio = async () => {
      setIsLoading(true);
      setError(null);
      setAudioSrc(null); // Reset audio source when fetching new audio
      
      try {
        if (!audioUrl) {
          throw new Error('Audio URL is missing');
        }

        // Remove 'voices/' prefix if it exists to prevent double prefix
        const formattedUrl = audioUrl.startsWith('voices/') ? audioUrl.substring(7) : audioUrl;

        const { data, error } = await supabase.storage
          .from('voices')
          .createSignedUrl(formattedUrl, 3600); // 1 hour expiry
        
        if (error) {
          if (error.message.includes('not_found') || error.statusCode === '404') {
            throw new Error('This audio message is no longer available. The file may have been deleted or moved.');
          }
          throw error;
        }
        
        if (!data?.signedUrl) {
          throw new Error('Failed to generate audio URL');
        }

        // Verify the audio file is accessible before setting it
        const response = await fetch(data.signedUrl, { method: 'HEAD' });
        if (!response.ok) {
          throw new Error('Audio file is not accessible');
        }
        
        setAudioSrc(data.signedUrl);
      } catch (error) {
        console.error('Error fetching audio:', error);
        let errorMessage = 'Unable to load the audio message';
        
        if (error instanceof Error) {
          // Provide user-friendly error messages
          if (error.message.includes('not_found') || error.message.includes('no longer available')) {
            errorMessage = error.message;
          } else if (error.message.includes('Invalid audio URL')) {
            errorMessage = 'The audio file location is invalid';
          } else if (error.message.includes('not accessible')) {
            errorMessage = 'The audio file cannot be accessed at this time';
          }
        }
        
        setError(errorMessage);
      } finally {
        setIsLoading(false);
      }
    };
    
    fetchAudio();
    fetchBookmarks();
  }, [audioUrl]);
  
  const fetchBookmarks = async () => {
    if (!user) return;
    
    try {
      const { data, error } = await supabase
        .from('bookmarks')
        .select('id, timestamp_sec, label')
        .eq('message_id', messageId)
        .eq('user_id', user.id)
        .order('timestamp_sec');
      
      if (error) {
        throw error;
      }
      
      setBookmarks(data || []);
    } catch (error) {
      console.error('Error fetching bookmarks:', error);
    }
  };
  
  useEffect(() => {
    setFavorite(isFavorited);
  }, [isFavorited]);
  
  useEffect(() => {
    const audio = audioRef.current;
    
    if (!audio) return;
    
    const updateTime = () => {
      setCurrentTime(audio.currentTime);
    };
    
    const handleEnded = () => {
      setIsPlaying(false);
      setCurrentTime(0);
    };

    const handleError = (e: ErrorEvent) => {
      console.error('Audio playback error:', e);
      setError('Failed to play the audio file');
      setIsPlaying(false);
    };
    
    audio.addEventListener('timeupdate', updateTime);
    audio.addEventListener('ended', handleEnded);
    audio.addEventListener('error', handleError);
    
    return () => {
      audio.removeEventListener('timeupdate', updateTime);
      audio.removeEventListener('ended', handleEnded);
      audio.removeEventListener('error', handleError);
    };
  }, []);
  
  const togglePlayPause = () => {
    if (!audioRef.current) return;
    
    if (isPlaying) {
      audioRef.current.pause();
    } else {
      audioRef.current.play().catch(error => {
        console.error('Playback failed:', error);
        setError('Unable to play the audio file');
        setIsPlaying(false);
      });
    }
    
    setIsPlaying(!isPlaying);
  };
  
  const skipTime = (seconds: number) => {
    if (!audioRef.current) return;
    
    const newTime = Math.max(0, Math.min(audioRef.current.currentTime + seconds, duration));
    audioRef.current.currentTime = newTime;
    setCurrentTime(newTime);
  };
  
  const seekToBookmark = (timestamp: number) => {
    if (!audioRef.current) return;
    
    audioRef.current.currentTime = timestamp;
    setCurrentTime(timestamp);
    
    if (!isPlaying) {
      audioRef.current.play().catch(error => {
        console.error('Playback failed:', error);
        setError('Unable to play the audio file');
        setIsPlaying(false);
      });
      setIsPlaying(true);
    }
  };
  
  const onProgressBarClick = (e: React.MouseEvent<HTMLDivElement>) => {
    if (!audioRef.current) return;
    
    const progressBar = e.currentTarget;
    const rect = progressBar.getBoundingClientRect();
    const clickPosition = (e.clientX - rect.left) / rect.width;
    const newTime = clickPosition * duration;
    
    audioRef.current.currentTime = newTime;
    setCurrentTime(newTime);
  };
  
  const toggleFavorite = async () => {
    if (!user) return;
    
    try {
      if (favorite) {
        // Remove favorite
        await supabase
          .from('favorites')
          .delete()
          .match({ user_id: user.id, message_id: messageId });
      } else {
        // Add favorite
        await supabase
          .from('favorites')
          .insert({ user_id: user.id, message_id: messageId });
      }
      
      setFavorite(!favorite);
    } catch (error) {
      console.error('Error toggling favorite:', error);
    }
  };
  
  const addBookmark = async () => {
    if (!user || !audioRef.current) return;
    
    const timestamp = audioRef.current.currentTime;
    const label = prompt('Enter a label for this bookmark:');
    
    if (!label) return;
    
    try {
      const { data, error } = await supabase
        .from('bookmarks')
        .insert({
          message_id: messageId,
          user_id: user.id,
          timestamp_sec: timestamp,
          label
        })
        .select()
        .single();
      
      if (error) throw error;
      
      if (data) {
        setBookmarks([...bookmarks, data]);
      }
      
    } catch (error) {
      console.error('Error adding bookmark:', error);
      alert('Failed to add bookmark');
    }
  };
  
  const deleteBookmark = async (bookmarkId: string) => {
    try {
      await supabase
        .from('bookmarks')
        .delete()
        .eq('id', bookmarkId);
      
      setBookmarks(bookmarks.filter(b => b.id !== bookmarkId));
    } catch (error) {
      console.error('Error deleting bookmark:', error);
      alert('Failed to delete bookmark');
    }
  };
  
  if (error) {
    return (
      <div className="bg-white rounded-lg shadow-sm p-4 border border-gray-200">
        <div className="text-error-600 text-sm flex items-center justify-center gap-2">
          <span>⚠️</span>
          <span>{error}</span>
        </div>
      </div>
    );
  }
  
  return (
    <div className="relative bg-white rounded-lg shadow-sm p-3 border border-gray-200">
      {audioSrc && (
        <audio ref={audioRef} src={audioSrc} preload="metadata" />
      )}
      
      <div className="space-y-3">
        <div className="flex items-center gap-3">
          <button
            type="button"
            onClick={() => skipTime(-10)}
            className="flex-shrink-0 h-8 w-8 rounded-full bg-gray-100 flex items-center justify-center text-gray-700 hover:bg-gray-200"
          >
            <Rewind size={16} />
          </button>
          
          <button
            type="button"
            onClick={togglePlayPause}
            disabled={isLoading || !audioSrc}
            className="flex-shrink-0 h-10 w-10 rounded-full bg-primary-100 flex items-center justify-center text-primary-700 disabled:opacity-50 hover:bg-primary-200"
          >
            {isPlaying ? <Pause size={20} /> : <Play size={20} />}
          </button>
          
          <button
            type="button"
            onClick={() => skipTime(10)}
            className="flex-shrink-0 h-8 w-8 rounded-full bg-gray-100 flex items-center justify-center text-gray-700 hover:bg-gray-200"
          >
            <FastForward size={16} />
          </button>
          
          <div className="flex-1">
            <div 
              className="h-2 bg-gray-200 rounded-full cursor-pointer relative overflow-hidden"
              onClick={onProgressBarClick}
            >
              <div 
                className="absolute left-0 top-0 h-full bg-primary-500 rounded-full"
                style={{ width: `${(currentTime / duration) * 100}%` }}
              />
              
              {/* Bookmark indicators */}
              {bookmarks.map((bookmark) => (
                <div
                  key={bookmark.id}
                  className="absolute top-0 h-full w-0.5 bg-accent-500"
                  style={{ left: `${(bookmark.timestamp_sec / duration) * 100}%` }}
                />
              ))}
            </div>
            
            <div className="flex justify-between text-xs text-gray-500 mt-1">
              <span>{formatDuration(currentTime)}</span>
              <span>{formatDuration(duration)}</span>
            </div>
          </div>
          
          <div className="flex items-center space-x-2">
            <button
              type="button"
              onClick={addBookmark}
              className="text-gray-400 hover:text-primary-500 focus:outline-none"
            >
              <Bookmark size={18} />
            </button>
            
            <button
              type="button"
              onClick={() => setShowBookmarks(!showBookmarks)}
              className={`text-gray-400 hover:text-primary-500 focus:outline-none ${showBookmarks ? 'text-primary-500' : ''}`}
            >
              <MessageSquare size={18} />
              {bookmarks.length > 0 && (
                <span className="absolute -top-1 -right-1 h-4 w-4 text-xs bg-accent-500 text-white rounded-full flex items-center justify-center">
                  {bookmarks.length}
                </span>
              )}
            </button>
            
            <button
              type="button"
              onClick={toggleFavorite}
              className={`focus:outline-none ${favorite ? 'text-amber-500' : 'text-gray-400 hover:text-amber-500'}`}
            >
              <Star size={18} />
            </button>
          </div>
        </div>
        
        {/* Bookmarks panel */}
        {showBookmarks && bookmarks.length > 0 && (
          <div className="mt-3 space-y-2">
            <h4 className="text-sm font-medium text-gray-900">Bookmarks</h4>
            <div className="space-y-1">
              {bookmarks.map((bookmark) => (
                <div
                  key={bookmark.id}
                  className="flex items-center justify-between p-2 rounded-md bg-gray-50 hover:bg-gray-100"
                >
                  <button
                    type="button"
                    onClick={() => seekToBookmark(bookmark.timestamp_sec)}
                    className="flex items-center space-x-2 text-sm text-gray-700 hover:text-primary-600"
                  >
                    <Play size={14} />
                    <span>{formatDuration(bookmark.timestamp_sec)}</span>
                    <span className="font-medium">{bookmark.label}</span>
                  </button>
                  
                  <button
                    type="button"
                    onClick={() => deleteBookmark(bookmark.id)}
                    className="text-gray-400 hover:text-error-500"
                  >
                    <span className="sr-only">Delete bookmark</span>
                    ×
                  </button>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default AudioPlayer;