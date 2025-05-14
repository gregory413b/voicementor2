import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuthStore } from '../../stores/authStore';
import { supabase } from '../../lib/supabase';
import { formatDate } from '../../lib/utils';
import Loading from '../../components/ui/Loading';
import { MessageSquare, User, Volume2 } from 'lucide-react';

interface RecentMessage {
  id: string;
  created_at: string;
  audio_url: string | null;
  text_transcript: string | null;
  unread_count: number;
  sender: {
    id: string;
    full_name: string;
  };
  conversation: {
    id: string;
    client: { id: string; full_name: string };
    mentor: { id: string; full_name: string };
  };
}

const Dashboard = () => {
  const [recentMessages, setRecentMessages] = useState<RecentMessage[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const { user, profile } = useAuthStore();
  const navigate = useNavigate();

  useEffect(() => {
    const fetchData = async () => {
      if (!user || !profile) return;

      setIsLoading(true);

      try {
        const { data: messagesData, error: messagesError } = await supabase
          .from('audio_messages')
          .select(`
            id,
            created_at,
            audio_url,
            text_transcript,
            sender:profiles!audio_messages_sender_id_fkey(id, full_name),
            conversation:conversations!audio_messages_conversation_id_fkey(
              id,
              client:profiles!conversations_client_id_fkey(id, full_name),
              mentor:profiles!conversations_mentor_id_fkey(id, full_name)
            )
          `)
          .order('created_at', { ascending: false });

        if (messagesError) throw messagesError;

        const processedMessages = messagesData
          .filter(msg => msg.conversation && msg.conversation.client && msg.conversation.mentor)
          .map(msg => ({
            ...msg,
            unread_count: Math.floor(Math.random() * 4), // Placeholder
            sender: Array.isArray(msg.sender) ? msg.sender[0] : msg.sender,
            conversation: {
              ...msg.conversation,
              client: Array.isArray(msg.conversation.client)
                ? msg.conversation.client[0]
                : msg.conversation.client,
              mentor: Array.isArray(msg.conversation.mentor)
                ? msg.conversation.mentor[0]
                : msg.conversation.mentor,
            },
          }));

        const latestMessages = processedMessages.reduce((acc, message) => {
          const exists = acc.find(m => m.conversation.id === message.conversation.id);
          if (!exists) acc.push(message);
          return acc;
        }, [] as RecentMessage[]);

        setRecentMessages(latestMessages);
      } catch (error) {
        console.error('Error fetching dashboard data:', error);
      } finally {
        setIsLoading(false);
      }
    };

    fetchData();
  }, [user, profile]);

  const getOtherParticipant = (message: RecentMessage) => {
    if (!profile) return null;
    return profile.role === 'client'
      ? message.conversation.mentor
      : message.conversation.client;
  };

  const handleContactClick = (message: RecentMessage) => {
    const otherPerson = getOtherParticipant(message);
    if (otherPerson) {
      navigate(`/messages/${otherPerson.id}`);
    }
  };

  if (isLoading) {
    return (
      <div className="h-64 flex items-center justify-center">
        <Loading />
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden">
        <div className="p-4 border-b border-gray-200">
          <h2 className="text-lg font-semibold text-gray-900">Recent Messages</h2>
        </div>

        {recentMessages.length === 0 ? (
          <div className="p-6 text-center">
            <MessageSquare className="mx-auto h-12 w-12 text-gray-400" />
            <h3 className="mt-2 text-sm font-medium text-gray-900">No messages</h3>
            <p className="mt-1 text-sm text-gray-500">
              Start a conversation with your contacts
            </p>
          </div>
        ) : (
          <div className="divide-y divide-gray-200">
            {recentMessages.map((message) => {
              const otherPerson = getOtherParticipant(message);
              if (!otherPerson) return null;

              return (
                <button
                  key={message.id}
                  onClick={() => handleContactClick(message)}
                  className="w-full p-4 hover:bg-gray-50 flex items-center space-x-4 text-left"
                >
                  <div className="flex-shrink-0">
                    <div className="h-12 w-12 rounded-full bg-gray-200 flex items-center justify-center text-gray-500">
                      <User className="h-6 w-6" />
                    </div>
                  </div>

                  <div className="flex-1 min-w-0">
                    <div className="flex items-center justify-between">
                      <p className="text-sm font-medium text-gray-900 truncate">
                        {otherPerson.full_name}
                      </p>
                      <p className="text-xs text-gray-500">
                        {formatDate(message.created_at)}
                      </p>
                    </div>

                    <div className="flex items-center mt-1">
                      {message.audio_url ? (
                        <div className="flex items-center text-gray-500 text-sm">
                          <Volume2 className="h-4 w-4 mr-1" />
                          <span>Audio Message</span>
                        </div>
                      ) : (
                        <p className="text-sm text-gray-500 truncate">
                          {message.text_transcript || 'No message content'}
                        </p>
                      )}

                      {message.unread_count > 0 && (
                        <div className="ml-2 bg-primary-500 text-white text-xs font-medium rounded-full h-5 w-5 flex items-center justify-center">
                          {message.unread_count}
                        </div>
                      )}
                    </div>
                  </div>
                </button>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
};

export default Dashboard;
