import { useState, useEffect } from 'react';
import { useAuthStore } from '../../stores/authStore';
import { supabase } from '../../lib/supabase';
import Loading from '../../components/ui/Loading';
import { User, Mail, UserCircle, AlertTriangle, CheckCircle } from 'lucide-react';

interface RelatedUser {
  id: string;
  full_name: string;
  role: string;
}

const Profile = () => {
  const { profile, user, fetchProfile } = useAuthStore();
  const [fullName, setFullName] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [message, setMessage] = useState<{ type: 'success' | 'error', text: string } | null>(null);
  const [mentor, setMentor] = useState<RelatedUser | null>(null);
  const [director, setDirector] = useState<RelatedUser | null>(null);
  const [clients, setClients] = useState<RelatedUser[]>([]);
  const [mentors, setMentors] = useState<RelatedUser[]>([]);
  
  useEffect(() => {
    if (profile) {
      setFullName(profile.full_name);
      
      // Fetch related users based on role
      fetchRelatedUsers();
    }
  }, [profile]);
  
  const fetchRelatedUsers = async () => {
    if (!user || !profile) return;
    
    setIsLoading(true);
    
    try {
      // If user has a mentor, fetch mentor details
      if (profile.mentor_id) {
        const { data: mentorData } = await supabase
          .from('profiles')
          .select('id, full_name, role')
          .eq('id', profile.mentor_id)
          .single();
        
        if (mentorData) {
          setMentor(mentorData);
        }
      }
      
      // If user has a director, fetch director details
      if (profile.director_id) {
        const { data: directorData } = await supabase
          .from('profiles')
          .select('id, full_name, role')
          .eq('id', profile.director_id)
          .single();
        
        if (directorData) {
          setDirector(directorData);
        }
      }
      
      // If user is a mentor, fetch their clients
      if (profile.role === 'mentor' || profile.role === 'training_director') {
        const { data: clientsData } = await supabase
          .from('profiles')
          .select('id, full_name, role')
          .eq('mentor_id', user.id);
        
        if (clientsData) {
          setClients(clientsData);
        }
      }
      
      // If user is a training director, fetch their mentors
      if (profile.role === 'training_director') {
        const { data: mentorsData } = await supabase
          .from('profiles')
          .select('id, full_name, role')
          .eq('director_id', user.id);
        
        if (mentorsData) {
          setMentors(mentorsData);
        }
      }
    } catch (error) {
      console.error('Error fetching related users:', error);
    } finally {
      setIsLoading(false);
    }
  };
  
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSaving(true);
    setMessage(null);
    
    try {
      const { error } = await supabase
        .from('profiles')
        .update({ full_name: fullName })
        .eq('id', user?.id);
      
      if (error) {
        throw error;
      }
      
      // Reload profile
      await fetchProfile();
      
      setMessage({
        type: 'success',
        text: 'Profile updated successfully'
      });
      
      // Clear success message after 3 seconds
      setTimeout(() => setMessage(null), 3000);
      
    } catch (error) {
      console.error('Error updating profile:', error);
      setMessage({
        type: 'error',
        text: 'Failed to update profile'
      });
    } finally {
      setIsSaving(false);
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
    <div className="max-w-2xl mx-auto">
      <h1 className="text-2xl font-bold text-gray-900 mb-6">Your Profile</h1>
      
      {message && (
        <div className={`mb-4 p-3 ${message.type === 'success' ? 'bg-success-50 border-success-100 text-success-700' : 'bg-error-50 border-error-100 text-error-700'} border rounded-md flex items-center`}>
          {message.type === 'success' ? (
            <CheckCircle className="h-5 w-5 mr-2 flex-shrink-0" />
          ) : (
            <AlertTriangle className="h-5 w-5 mr-2 flex-shrink-0" />
          )}
          <span>{message.text}</span>
        </div>
      )}
      
      <div className="bg-white shadow rounded-lg overflow-hidden">
        <div className="p-6 border-b border-gray-200">
          <h2 className="text-lg font-medium text-gray-900">Account Information</h2>
          <p className="mt-1 text-sm text-gray-500">Manage your personal information and role.</p>
        </div>
        
        <div className="p-6 space-y-6">
          <div>
            <div className="flex items-center mb-4">
              <div className="h-16 w-16 rounded-full bg-primary-100 flex items-center justify-center text-primary-800">
                <UserCircle className="h-8 w-8" />
              </div>
              <div className="ml-4">
                <p className="text-lg font-medium text-gray-900">{profile?.full_name}</p>
                <p className="text-sm text-gray-500 capitalize">{profile?.role}</p>
              </div>
            </div>
          </div>
          
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label htmlFor="fullName" className="block text-sm font-medium text-gray-700">
                Full Name
              </label>
              <div className="mt-1 relative">
                <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                  <User className="h-5 w-5 text-gray-400" />
                </div>
                <input
                  id="fullName"
                  name="fullName"
                  type="text"
                  required
                  value={fullName}
                  onChange={(e) => setFullName(e.target.value)}
                  className="appearance-none block w-full pl-10 pr-3 py-2 border border-gray-300 rounded-md shadow-sm placeholder-gray-400 focus:outline-none focus:ring-primary-500 focus:border-primary-500 sm:text-sm"
                />
              </div>
            </div>
            
            <div>
              <label className="block text-sm font-medium text-gray-700">
                Email Address
              </label>
              <div className="mt-1 relative">
                <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                  <Mail className="h-5 w-5 text-gray-400" />
                </div>
                <input
                  type="email"
                  readOnly
                  value={user?.email || ''}
                  className="appearance-none block w-full pl-10 pr-3 py-2 border border-gray-300 rounded-md shadow-sm bg-gray-50 sm:text-sm"
                />
              </div>
              <p className="mt-1 text-xs text-gray-500">Email cannot be changed</p>
            </div>
            
            <div>
              <label className="block text-sm font-medium text-gray-700">
                Role
              </label>
              <div className="mt-1">
                <input
                  type="text"
                  readOnly
                  value={profile?.role ? profile.role.replace('_', ' ').replace(/\b\w/g, c => c.toUpperCase()) : ''}
                  className="appearance-none block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm bg-gray-50 sm:text-sm"
                />
              </div>
              <p className="mt-1 text-xs text-gray-500">Role is assigned by administration</p>
            </div>
            
            <div>
              <button
                type="submit"
                disabled={isSaving}
                className="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-primary-600 hover:bg-primary-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-primary-500 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {isSaving ? 'Saving...' : 'Save Changes'}
              </button>
            </div>
          </form>
        </div>
      </div>
      
      {/* Relationships Section */}
      <div className="mt-8 bg-white shadow rounded-lg overflow-hidden">
        <div className="p-6 border-b border-gray-200">
          <h2 className="text-lg font-medium text-gray-900">Your Relationships</h2>
          <p className="mt-1 text-sm text-gray-500">
            View your mentor-client relationships in the tiered system.
          </p>
        </div>
        
        <div className="p-6 space-y-6">
          {mentor && (
            <div>
              <h3 className="text-sm font-medium text-gray-700 mb-2">Your Mentor</h3>
              <div className="bg-gray-50 p-3 rounded-md flex items-center">
                <div className="h-10 w-10 rounded-full bg-primary-100 flex items-center justify-center text-primary-800">
                  <User className="h-5 w-5" />
                </div>
                <div className="ml-3">
                  <p className="text-sm font-medium text-gray-900">{mentor.full_name}</p>
                  <p className="text-xs text-gray-500 capitalize">{mentor.role}</p>
                </div>
              </div>
            </div>
          )}
          
          {director && (
            <div>
              <h3 className="text-sm font-medium text-gray-700 mb-2">Your Training Director</h3>
              <div className="bg-gray-50 p-3 rounded-md flex items-center">
                <div className="h-10 w-10 rounded-full bg-primary-100 flex items-center justify-center text-primary-800">
                  <User className="h-5 w-5" />
                </div>
                <div className="ml-3">
                  <p className="text-sm font-medium text-gray-900">{director.full_name}</p>
                  <p className="text-xs text-gray-500 capitalize">{director.role}</p>
                </div>
              </div>
            </div>
          )}
          
          {clients.length > 0 && (
            <div>
              <h3 className="text-sm font-medium text-gray-700 mb-2">Your Clients ({clients.length})</h3>
              <div className="space-y-2">
                {clients.map(client => (
                  <div key={client.id} className="bg-gray-50 p-3 rounded-md flex items-center">
                    <div className="h-10 w-10 rounded-full bg-primary-100 flex items-center justify-center text-primary-800">
                      <User className="h-5 w-5" />
                    </div>
                    <div className="ml-3">
                      <p className="text-sm font-medium text-gray-900">{client.full_name}</p>
                      <p className="text-xs text-gray-500 capitalize">{client.role}</p>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
          
          {mentors.length > 0 && (
            <div>
              <h3 className="text-sm font-medium text-gray-700 mb-2">Your Mentors ({mentors.length})</h3>
              <div className="space-y-2">
                {mentors.map(mentor => (
                  <div key={mentor.id} className="bg-gray-50 p-3 rounded-md flex items-center">
                    <div className="h-10 w-10 rounded-full bg-primary-100 flex items-center justify-center text-primary-800">
                      <User className="h-5 w-5" />
                    </div>
                    <div className="ml-3">
                      <p className="text-sm font-medium text-gray-900">{mentor.full_name}</p>
                      <p className="text-xs text-gray-500 capitalize">{mentor.role}</p>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
          
          {!mentor && !director && clients.length === 0 && mentors.length === 0 && (
            <div className="text-center py-4">
              <p className="text-sm text-gray-500">
                No relationships have been established yet.
              </p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default Profile;