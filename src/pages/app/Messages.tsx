import { useState, useEffect } from 'react';
import { useParams } from 'react-router-dom';
import { supabase } from '../../lib/supabase';
import { useAuthStore } from '../../stores/authStore';
import AudioPlayer from '../../components/conversations/AudioPlayer';
import MessageInput from '../../components/conversations/MessageInput';
import { formatDate } from '../../lib/utils';
import Loading from '../../components/ui/Loading';
import { MessageSquare } from 'lucide-react';

interface Message {
  id: string;
  created_at: string;
  sender_id: string;
  audio_url?: string;
  duration?: number;
  text_transcript?: string;
  sender: {
    full_name: string;
    id: string;
  };
}

const Messages = () => {
  const { contactId } = useParams<{ contactId: string }>();
  const [messages, setMessages] = useState<Message[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [conversationId, setConversationId] = useState<string | null>(null);
  const { user } = useAuthStore();
  
  useEffect(() => {
    const fetchMessages = async () => {
      if (!contactId || !user) return;
      
      setIsLoading(true);
      setError(null);
      
      try {
        // First, find existing conversation
        const { data: existingConv, error: convError } = await supabase
          .from('conversations')
          .select('*')
          .or(`and(client_id.eq.${user.id},mentor_id.eq.${contactId}),and(client_id.eq.${contactId},mentor_id.eq.${user.id})`)
          .limit(1);
        
        if (convError) throw convError;
        
        let foundConversationId = existingConv && existingConv.length > 0 ? existingConv[0]?.id : null;
        
        if (!foundConversationId) {
          // Create new conversation
          const { data: newConv, error: createError } = await supabase
            .from('conversations')
            .insert({
              client_id: user.id,
              mentor_id: contactId,
            })
            .select()
            .single();
          
          if (createError) throw createError;
          foundConversationId = newConv.id;
        }
        
        setConversationId(foundConversationId);
        
        // Fetch all messages for this conversation
        const { data: messages, error: messagesError } = await supabase
          .from('audio_messages')
          .select(`
            id, 
            created_at, 
            sender_id, 
            audio_url, 
            duration,
            text_transcript,
            sender:profiles!audio_messages_sender_id_fkey(id, full_name)
          `)
          .eq('conversation_id', foundConversationId)
          .order('created_at');
        
        if (messagesError) throw messagesError;
        
        // Process and set messages
        const processedMessages = (messages || []).map(msg => ({
          ...msg,
          sender: Array.isArray(msg.sender) ? msg.sender[0] : msg.sender
        }));
        
        setMessages(processedMessages);
      } catch (error) {
        console.error('Error fetching messages:', error);
        setError('Failed to load messages');
      } finally {
        setIsLoading(false);
      }
    };
    
    fetchMessages();
    
    // Set up real-time subscription for new messages
    let subscription: ReturnType<typeof supabase.channel> | null = null;
    
    if (conversationId) {
      subscription = supabase
        .channel(`messages-${conversationId}`)
        .on('postgres_changes', 
            { 
              event: 'INSERT', 
              schema: 'public', 
              table: 'audio_messages',
              filter: `conversation_id=eq.${conversationId}`
            },
            async (payload) => {
              const { data: senderData, error: senderError } = await supabase
                .from('profiles')
                .select('id, full_name')
                .eq('id', payload.new.sender_id)
                .single();
              
              if (!senderError && senderData) {
                setMessages(prev => [...prev, {
                  ...payload.new as Message,
                  sender: senderData
                }]);
              }
            }
        )
        .subscribe();
    }
    
    return () => {
      if (subscription) {
        subscription.unsubscribe();
      }
    };
  }, [contactId, user]);
  
  if (isLoading) {
    return (
      <div className="h-64 flex items-center justify-center">
        <Loading />
      </div>
    );
  }
  
  if (error) {
    return (
      <div className="text-center py-12">
        <MessageSquare className="mx-auto h-12 w-12 text-gray-400" />
        <h3 className="mt-2 text-lg font-medium text-gray-900">Error</h3>
        <p className="mt-1 text-sm text-gray-500">{error}</p>
      </div>
    );
  }
  
  return (
    <div className="flex flex-col h-[calc(100vh-150px)]">
      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {messages.length === 0 ? (
          <div className="text-center py-12">
            <MessageSquare className="mx-auto h-12 w-12 text-gray-400" />
            <h3 className="mt-2 text-lg font-medium text-gray-900">No messages yet</h3>
            <p className="mt-1 text-sm text-gray-500">
              Start the conversation by sending a message.
            </p>
          </div>
        ) : (
          messages.map((message) => {
            const isOwnMessage = message.sender_id === user?.id;
            const isTextMessage = !message.audio_url && message.text_transcript;
            
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
                  
                  {isTextMessage ? (
                    <div className={`rounded-lg px-4 py-2 ${
                      isOwnMessage
                        ? 'bg-primary-600 text-white'
                        : 'bg-white border border-gray-200 text-gray-900'
                    }`}>
                      <p className="text-sm whitespace-pre-wrap">{message.text_transcript}</p>
                    </div>
                  ) : (
                    <div className={`rounded-lg ${isOwnMessage ? 'bg-primary-50' : 'bg-white border border-gray-200'}`}>
                      <AudioPlayer
                        messageId={message.id}
                        audioUrl={message.audio_url!}
                        duration={message.duration!}
                      />
                    </div>
                  )}
                </div>
              </div>
            );
          })
        )}
      </div>
      
      {conversationId && (
        <MessageInput
          conversationId={conversationId}
          onMessageSent={() => {}}
        />
      )}
    </div>
  );
};

export default Messages;