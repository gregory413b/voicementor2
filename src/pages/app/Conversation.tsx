import { useState, useEffect } from 'react';
import { useParams } from 'react-router-dom';
import { supabase } from '../../lib/supabase';
import { useAuthStore } from '../../stores/authStore';
import AudioRecorder from '../../components/conversations/AudioRecorder';
import AudioPlayer from '../../components/conversations/AudioPlayer';
import { formatDate } from '../../lib/utils';
import Loading from '../../components/ui/Loading';
import { MessageSquare, User } from 'lucide-react';

interface AudioMessage {
  id: string;
  created_at: string;
  sender_id: string;
  audio_url: string;
  duration: number;
  sender: {
    full_name: string;
    id: string;
  };
}

interface Participant {
  user_id: string;
  role: 'client' | 'mentor' | 'training_director';
  profile: {
    full_name: string;
  };
}

const Conversation = () => {
  const { id: conversationId } = useParams<{ id: string }>();
  const [messages, setMessages] = useState<AudioMessage[]>([]);
  const [participants, setParticipants] = useState<Participant[]>([]);
  const [favorites, setFavorites] = useState<Record<string, boolean>>({});
  const [isLoading, setIsLoading] = useState(true);
  const { user } = useAuthStore();
  
  useEffect(() => {
    if (!conversationId || !user) return;
    
    const fetchMessages = async () => {
      setIsLoading(true);
      
      try {
        // Fetch messages
        const { data: messagesData, error: messagesError } = await supabase
          .from('audio_messages')
          .select(`
            id, 
            created_at, 
            sender_id, 
            audio_url, 
            duration,
            sender:profiles!audio_messages_sender_id_fkey(id, full_name)
          `)
          .eq('conversation_id', conversationId)
          .order('created_at', { ascending: true });
        
        if (messagesError) {
          throw messagesError;
        }
        
        // Process messages data
        const processedMessages = messagesData.map(msg => ({
          ...msg,
          sender: Array.isArray(msg.sender) ? msg.sender[0] : msg.sender
        }));
        
        setMessages(processedMessages);
        
        // Fetch participant details
        const { data: participantsData, error: participantsError } = await supabase
          .from('conversation_participants')
          .select(`
            user_id,
            role,
            profile:profiles!conversation_participants_user_id_fkey(full_name)
          `)
          .eq('conversation_id', conversationId);
        
        if (participantsError) {
          throw participantsError;
        }
        
        // Process participants data
        const processedParticipants = participantsData.map(p => ({
          ...p,
          profile: Array.isArray(p.profile) ? p.profile[0] : p.profile
        }));
        
        setParticipants(processedParticipants);
        
        // Fetch favorites
        const { data: favoritesData, error: favoritesError } = await supabase
          .from('favorites')
          .select('message_id')
          .eq('user_id', user.id);
        
        if (favoritesError) {
          throw favoritesError;
        }
        
        // Create a map of message_id -> true for favorited messages
        const favoritesMap = favoritesData.reduce<Record<string, boolean>>((acc, fav) => {
          acc[fav.message_id] = true;
          return acc;
        }, {});
        
        setFavorites(favoritesMap);
        
      } catch (error) {
        console.error('Error fetching conversation data:', error);
      } finally {
        setIsLoading(false);
      }
    };
    
    fetchMessages();
    
    // Subscribe to new messages
    const subscription = supabase
      .channel('conversation-messages')
      .on('postgres_changes', 
          { event: 'INSERT', schema: 'public', table: 'audio_messages', filter: `conversation_id=eq.${conversationId}` },
          async (payload) => {
            // When a new message is inserted, fetch the sender details
            const { data: senderData } = await supabase
              .from('profiles')
              .select('id, full_name')
              .eq('id', payload.new.sender_id)
              .single();
            
            // Add the new message to our state
            setMessages(prev => [...prev, {
              ...payload.new as AudioMessage,
              sender: senderData || { id: payload.new.sender_id, full_name: 'Unknown User' }
            }]);
          }
      )
      .subscribe();
    
    return () => {
      subscription.unsubscribe();
    };
  }, [conversationId, user]);
  
  const handleMessageSent = () => {
    // This is called after a new message is sent
    // We don't need to do anything here as the real-time subscription will update the UI
  };
  
  if (isLoading) {
    return (
      <div className="h-64 flex items-center justify-center">
        <Loading />
      </div>
    );
  }
  
  return (
    <div className="flex flex-col h-[calc(100vh-150px)]">
      <div className="border-b border-gray-200 bg-white py-4 px-6 shadow-sm">
        <div className="flex items-center space-x-3">
          <div className="h-10 w-10 rounded-full bg-primary-100 flex items-center justify-center text-primary-800">
            <User className="h-5 w-5" />
          </div>
          
          <div>
            <h1 className="text-lg font-semibold text-gray-900">
              {participants
                .filter(p => p.user_id !== user?.id)
                .map(p => p.profile.full_name)
                .join(', ')}
            </h1>
            <p className="text-sm text-gray-500">
              {participants.length} participants
            </p>
          </div>
        </div>
      </div>
      
      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {messages.length === 0 ? (
          <div className="text-center py-12">
            <MessageSquare className="mx-auto h-12 w-12 text-gray-400" />
            <h3 className="mt-2 text-lg font-medium text-gray-900">No messages yet</h3>
            <p className="mt-1 text-sm text-gray-500">
              Start the conversation by sending a voice message.
            </p>
          </div>
        ) : (
          messages.map((message) => {
            const isOwnMessage = message.sender_id === user?.id;
            
            return (
              <div
                key={message.id}
                className={`flex ${isOwnMessage ? 'justify-end' : 'justify-start'}`}
              >
                <div className={`max-w-[80%] ${isOwnMessage ? 'order-1' : 'order-2'}`}>
                  <div className={`flex items-center mb-1 ${isOwnMessage ? 'justify-end' : 'justify-start'}`}>
                    <span className="text-xs text-gray-500">
                      {formatDate(message.created_at)}
                    </span>
                    <span className="mx-2 text-xs text-gray-400">•</span>
                    <span className={`text-xs font-medium ${isOwnMessage ? 'text-primary-600' : 'text-gray-700'}`}>
                      {message.sender.full_name}
                    </span>
                  </div>
                  
                  <AudioPlayer
                    messageId={message.id}
                    audioUrl={message.audio_url}
                    duration={message.duration}
                    isFavorited={!!favorites[message.id]}
                  />
                </div>
              </div>
            );
          })
        )}
      </div>
      
      <AudioRecorder
        conversationId={conversationId || ''}
        onMessageSent={handleMessageSent}
      />
    </div>
  );
};

export default Conversation;