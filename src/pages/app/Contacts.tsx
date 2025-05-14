import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuthStore } from '../../stores/authStore';
import { supabase } from '../../lib/supabase';
import Loading from '../../components/ui/Loading';
import { User, Search } from 'lucide-react';

interface Contact {
  id: string;
  full_name: string;
  role: string;
  is_mentor?: boolean;
  is_client?: boolean;
}

const Contacts = () => {
  const [contacts, setContacts] = useState<Contact[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const { user, profile } = useAuthStore();
  const navigate = useNavigate();
  
  useEffect(() => {
    const fetchContacts = async () => {
      if (!user || !profile) return;
      
      setIsLoading(true);
      
      try {
        let query = supabase
          .from('profiles')
          .select('id, full_name, role, mentor_id, director_id')
          .neq('id', user.id);
        
        // Filter based on role relationships
        if (profile.role === 'client') {
          // Clients can only see their mentor
          query = query.eq('id', profile.mentor_id);
        } else if (profile.role === 'mentor') {
          // Mentors can see their clients and their director
          query = query.or(`id.eq.${profile.director_id},mentor_id.eq.${user.id}`);
        } else if (profile.role === 'training_director') {
          // First, fetch all mentor IDs for this director
          const { data: mentors, error: mentorsError } = await supabase
            .from('profiles')
            .select('id')
            .eq('director_id', user.id);
            
          if (mentorsError) throw mentorsError;
          
          const mentorIds = mentors.map(mentor => mentor.id);
          
          if (mentorIds.length > 0) {
            // Directors can see all their mentors and their mentors' clients
            query = query.or(`director_id.eq.${user.id},id.in.(${mentorIds.join(',')}),mentor_id.in.(${mentorIds.join(',')})`);
          } else {
            // If no mentors, only show direct relationships
            query = query.eq('director_id', user.id);
          }
        }
        
        const { data, error } = await query;
        
        if (error) {
          throw error;
        }
        
        // Process the contacts
        const processedContacts = data.map(contact => ({
          ...contact,
          is_mentor: contact.id === profile.mentor_id,
          is_client: profile.role === 'mentor' && contact.mentor_id === user.id,
        }));
        
        setContacts(processedContacts);
      } catch (error) {
        console.error('Error fetching contacts:', error);
      } finally {
        setIsLoading(false);
      }
    };
    
    fetchContacts();
  }, [user, profile]);
  
  const handleContactClick = (contact: Contact) => {
    navigate(`/messages/${contact.id}`);
  };
  
  const filteredContacts = contacts.filter(contact =>
    contact.full_name.toLowerCase().includes(searchQuery.toLowerCase())
  );
  
  if (isLoading) {
    return (
      <div className="h-64 flex items-center justify-center">
        <Loading />
      </div>
    );
  }
  
  return (
    <div className="space-y-6">
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
        <h1 className="text-2xl font-bold text-gray-900">Contacts</h1>
        <p className="mt-1 text-sm text-gray-500">
          {profile?.role === 'client'
            ? 'Your mentor and support team'
            : profile?.role === 'mentor'
            ? 'Your clients and training director'
            : 'Your mentors and their clients'}
        </p>
      </div>
      
      {contacts.length > 0 && (
        <div className="relative">
          <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
            <Search className="h-5 w-5 text-gray-400" />
          </div>
          <input
            type="text"
            placeholder="Search contacts..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="block w-full pl-10 pr-3 py-2 border border-gray-300 rounded-md leading-5 bg-white placeholder-gray-500 focus:outline-none focus:placeholder-gray-400 focus:ring-1 focus:ring-primary-500 focus:border-primary-500 sm:text-sm"
          />
        </div>
      )}
      
      {filteredContacts.length === 0 ? (
        <div className="text-center py-12 bg-white rounded-lg border border-gray-200">
          <User className="mx-auto h-12 w-12 text-gray-400" />
          <h3 className="mt-2 text-sm font-medium text-gray-900">No contacts</h3>
          <p className="mt-1 text-sm text-gray-500">
            {searchQuery
              ? 'No contacts match your search'
              : 'Your contacts will appear here'}
          </p>
        </div>
      ) : (
        <div className="bg-white rounded-lg border border-gray-200 divide-y divide-gray-200">
          {filteredContacts.map((contact) => (
            <button
              key={contact.id}
              onClick={() => handleContactClick(contact)}
              className="w-full p-4 hover:bg-gray-50 transition-colors duration-150 text-left"
            >
              <div className="flex items-center space-x-4">
                <div className="flex-shrink-0">
                  <div className="h-10 w-10 rounded-full bg-primary-100 flex items-center justify-center text-primary-800">
                    <User className="h-5 w-5" />
                  </div>
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-gray-900 truncate">
                    {contact.full_name}
                  </p>
                  <p className="text-xs text-gray-500 capitalize">
                    {contact.is_mentor
                      ? 'Your Mentor'
                      : contact.is_client
                      ? 'Your Client'
                      : contact.role.replace('_', ' ')}
                  </p>
                </div>
              </div>
            </button>
          ))}
        </div>
      )}
    </div>
  );
};

export default Contacts