import { Link, useLocation } from 'react-router-dom';
import { Home, MessageSquare, FolderHeart, Users } from 'lucide-react';

const BottomNav = () => {
  const location = useLocation();
  
  const navigation = [
    { name: 'Dashboard', href: '/dashboard', icon: Home },
    { name: 'Messages', href: '/messages', icon: MessageSquare },
    { name: 'Folders', href: '/folders', icon: FolderHeart },
    { name: 'Contacts', href: '/contacts', icon: Users },
  ];
  
  return (
    <nav className="fixed bottom-0 left-0 right-0 bg-white border-t border-gray-200">
      <div className="max-w-screen-xl mx-auto px-4">
        <div className="flex justify-around">
          {navigation.map((item) => {
            const isActive = location.pathname === item.href;
            
            return (
              <Link
                key={item.name}
                to={item.href}
                className={`flex flex-col items-center py-2 px-3 text-sm ${
                  isActive
                    ? 'text-primary-600'
                    : 'text-gray-500 hover:text-gray-900'
                }`}
              >
                <item.icon className="h-6 w-6" />
                <span className="mt-1 text-xs">{item.name}</span>
              </Link>
            );
          })}
        </div>
      </div>
    </nav>
  );
};

export default BottomNav;