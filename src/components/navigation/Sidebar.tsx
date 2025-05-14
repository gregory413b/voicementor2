import { Link, useLocation } from 'react-router-dom';
import { Square as MicSquare, Home, MessageSquare, FolderHeart, X, Users, UserCog } from 'lucide-react';
import { useAuthStore } from '../../stores/authStore';
import { cn } from '../../lib/utils';

interface SidebarProps {
  isOpen: boolean;
  onClose: () => void;
}

const Sidebar = ({ isOpen, onClose }: SidebarProps) => {
  const location = useLocation();
  const { profile } = useAuthStore();
  
  const navigation = [
    { name: 'Dashboard', href: '/dashboard', icon: Home },
    { name: 'Messages', href: '/conversations', icon: MessageSquare },
    { name: 'Saved', href: '/saved', icon: FolderHeart },
  ];
  
  // Add role-specific items
  if (profile?.role === 'mentor' || profile?.role === 'training_director') {
    navigation.push({ name: 'My Clients', href: '/clients', icon: Users });
  }
  
  if (profile?.role === 'training_director') {
    navigation.push({ name: 'My Mentors', href: '/mentors', icon: UserCog });
  }
  
  return (
    <>
      {/* Mobile overlay */}
      {isOpen && (
        <div
          className="fixed inset-0 z-20 bg-gray-900/80 backdrop-blur-sm md:hidden"
          onClick={onClose}
        />
      )}
      
      {/* Sidebar */}
      <div
        className={cn(
          "fixed inset-y-0 left-0 z-20 w-64 bg-primary-900 transition-transform duration-300 ease-in-out md:translate-x-0 md:z-0",
          isOpen ? "translate-x-0" : "-translate-x-full"
        )}
      >
        <div className="flex h-16 shrink-0 items-center justify-between px-6 border-b border-primary-800">
          <div className="flex items-center">
            <MicSquare className="h-8 w-8 text-white" />
            <span className="ml-2 text-xl font-semibold text-white">VoiceLink</span>
          </div>
          <button
            type="button"
            className="md:hidden text-white"
            onClick={onClose}
          >
            <X className="h-6 w-6" />
          </button>
        </div>
        
        <nav className="mt-5 px-4 space-y-1">
          {navigation.map((item) => (
            <Link
              key={item.name}
              to={item.href}
              className={cn(
                "flex items-center px-2 py-2 text-base font-medium rounded-md transition-colors",
                location.pathname === item.href
                  ? "bg-primary-800 text-white"
                  : "text-primary-100 hover:bg-primary-800 hover:text-white"
              )}
            >
              <item.icon className="mr-3 h-5 w-5 flex-shrink-0" />
              {item.name}
            </Link>
          ))}
        </nav>
        
        <div className="absolute bottom-0 w-full px-6 py-4">
          <div className="flex items-center space-x-2">
            <div className="h-8 w-8 rounded-full bg-primary-700 flex items-center justify-center">
              <span className="text-white text-sm font-medium">
                {profile?.full_name?.[0] || 'U'}
              </span>
            </div>
            <div>
              <p className="text-sm font-medium text-white truncate">{profile?.full_name || 'User'}</p>
              <p className="text-xs text-primary-300 capitalize">{profile?.role || 'Loading...'}</p>
            </div>
          </div>
        </div>
      </div>
    </>
  );
};

export default Sidebar;