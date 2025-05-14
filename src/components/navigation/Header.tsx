import { useNavigate } from 'react-router-dom';
import { Menu, User } from 'lucide-react';
import { useAuthStore } from '../../stores/authStore';

interface HeaderProps {
  onMenuClick: () => void;
}

const Header = ({ onMenuClick }: HeaderProps) => {
  const navigate = useNavigate();
  const { profile, signOut } = useAuthStore();
  
  const handleSignOut = async () => {
    await signOut();
    navigate('/login');
  };
  
  return (
    <header className="sticky top-0 z-10 flex h-16 shrink-0 items-center gap-x-4 border-b border-gray-200 bg-white px-4 shadow-sm sm:gap-x-6 sm:px-6 lg:px-8">
      <button 
        type="button" 
        className="-m-2.5 p-2.5 text-gray-700 md:hidden"
        onClick={onMenuClick}
      >
        <span className="sr-only">Open sidebar</span>
        <Menu className="h-6 w-6" aria-hidden="true" />
      </button>
      
      <div className="flex flex-1 gap-x-4 self-stretch lg:gap-x-6 justify-end">
        <div className="flex items-center gap-x-4 lg:gap-x-6">
          <div className="relative">
            <button 
              type="button"
              className="flex items-center gap-x-2 rounded-full bg-gray-100 p-2 text-sm font-semibold leading-6 text-gray-900"
              onClick={() => navigate('/profile')}
            >
              <User className="h-5 w-5 text-gray-500" aria-hidden="true" />
              <span>{profile?.full_name || 'User'}</span>
            </button>
          </div>
          
          <div className="hidden sm:block sm:h-6 sm:w-px sm:bg-gray-200" aria-hidden="true" />
          
          <button
            type="button"
            className="text-sm font-semibold leading-6 text-gray-900"
            onClick={handleSignOut}
          >
            Sign out
          </button>
        </div>
      </div>
    </header>
  );
};

export default Header;