/*
  # Initialize Tiered Voice Messaging App Schema
  
  1. New Tables
    - `profiles` - Stores user profile data and hierarchy relationships
    - `conversations` - Stores conversations between clients and mentors
    - `conversation_participants` - Maps users to conversations they participate in
    - `audio_messages` - Stores voice messages with metadata
    - `bookmarks` - Stores time-stamped bookmarks on audio messages
    - `favorites` - Tracks which messages users have favorited
    - `folders` - User-created folders for organizing messages
    - `folder_items` - Maps messages to folders
  
  2. Security
    - Enable RLS on all tables
    - Add policies for proper tiered access control
    - Create helper function for checking conversation membership
*/

-- Helper function to check if current user is a conversation member
CREATE OR REPLACE FUNCTION is_conversation_member(conv_uuid UUID)
RETURNS BOOLEAN LANGUAGE SQL SECURITY DEFINER AS $$
  SELECT EXISTS(
    SELECT 1 FROM conversation_participants
    WHERE conversation_id = conv_uuid
    AND user_id = auth.uid()
  );
$$;

-- PROFILES TABLE
CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  role TEXT NOT NULL CHECK (role IN ('client', 'mentor', 'training_director')),
  mentor_id UUID REFERENCES profiles(id),
  director_id UUID REFERENCES profiles(id),
  full_name TEXT NOT NULL,
  avatar_url TEXT
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Profile policies
CREATE POLICY "Users can read all profiles"
  ON profiles FOR SELECT
  USING (true);

CREATE POLICY "Users can update their own profile"
  ON profiles FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- CONVERSATIONS TABLE
CREATE TABLE IF NOT EXISTS conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  client_id UUID NOT NULL REFERENCES profiles(id),
  mentor_id UUID NOT NULL REFERENCES profiles(id)
);

ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;

-- CONVERSATION PARTICIPANTS TABLE
CREATE TABLE IF NOT EXISTS conversation_participants (
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('client', 'mentor', 'training_director')),
  PRIMARY KEY (conversation_id, user_id)
);

ALTER TABLE conversation_participants ENABLE ROW LEVEL SECURITY;

-- Conversation policies
CREATE POLICY "Users can view conversations they participate in"
  ON conversations FOR SELECT
  USING (
    client_id = auth.uid() 
    OR mentor_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM profiles mentor
      WHERE mentor.id = mentor_id
      AND mentor.director_id = auth.uid()
    )
  );

CREATE POLICY "Clients can create conversations with their mentor"
  ON conversations FOR INSERT
  WITH CHECK (
    client_id = auth.uid()
    OR (
      mentor_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM profiles
        WHERE id = client_id AND mentor_id = auth.uid()
      )
    )
  );

-- Conversation participants policies
CREATE POLICY "Users can view participants of their conversations"
  ON conversation_participants FOR SELECT
  USING (is_conversation_member(conversation_id));

-- AUDIO MESSAGES TABLE
CREATE TABLE IF NOT EXISTS audio_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES profiles(id),
  audio_url TEXT NOT NULL,
  duration NUMERIC NOT NULL,
  text_transcript TEXT
);

ALTER TABLE audio_messages ENABLE ROW LEVEL SECURITY;

-- Audio messages policies
CREATE POLICY "Conversation members can read messages"
  ON audio_messages FOR SELECT
  USING (is_conversation_member(conversation_id));

CREATE POLICY "Conversation members can add messages"
  ON audio_messages FOR INSERT
  WITH CHECK (
    is_conversation_member(conversation_id)
    AND sender_id = auth.uid()
  );

CREATE POLICY "Senders can delete their own messages"
  ON audio_messages FOR DELETE
  USING (sender_id = auth.uid());

-- BOOKMARKS TABLE
CREATE TABLE IF NOT EXISTS bookmarks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  message_id UUID NOT NULL REFERENCES audio_messages(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id),
  timestamp_sec NUMERIC NOT NULL,
  label TEXT NOT NULL
);

ALTER TABLE bookmarks ENABLE ROW LEVEL SECURITY;

-- Bookmarks policies
CREATE POLICY "Users can manage their own bookmarks"
  ON bookmarks FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- FAVORITES TABLE
CREATE TABLE IF NOT EXISTS favorites (
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  message_id UUID REFERENCES audio_messages(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, message_id)
);

ALTER TABLE favorites ENABLE ROW LEVEL SECURITY;

-- Favorites policies
CREATE POLICY "Users can manage their own favorites"
  ON favorites FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- FOLDERS TABLE
CREATE TABLE IF NOT EXISTS folders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  owner_id UUID NOT NULL REFERENCES profiles(id),
  name TEXT NOT NULL
);

ALTER TABLE folders ENABLE ROW LEVEL SECURITY;

-- Folders policies
CREATE POLICY "Users can manage their own folders"
  ON folders FOR ALL
  USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());

-- FOLDER ITEMS TABLE
CREATE TABLE IF NOT EXISTS folder_items (
  folder_id UUID REFERENCES folders(id) ON DELETE CASCADE,
  message_id UUID REFERENCES audio_messages(id) ON DELETE CASCADE,
  added_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (folder_id, message_id)
);

ALTER TABLE folder_items ENABLE ROW LEVEL SECURITY;

-- Folder items policies
CREATE POLICY "Users can manage items in their folders"
  ON folder_items FOR ALL
  USING (
    folder_id IN (SELECT id FROM folders WHERE owner_id = auth.uid())
  )
  WITH CHECK (
    folder_id IN (SELECT id FROM folders WHERE owner_id = auth.uid())
    AND EXISTS (
      SELECT 1 FROM audio_messages m
      WHERE m.id = message_id
      AND is_conversation_member(m.conversation_id)
    )
  );

-- Set up storage bucket for voice messages
INSERT INTO storage.buckets (id, name, public) VALUES ('voices', 'voices', false)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for secure audio file access
CREATE POLICY "Only conversation members can read audio files"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'voices'
    AND is_conversation_member((storage.foldername(name))[1]::uuid)
  );

CREATE POLICY "Only conversation members can upload audio files"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'voices'
    AND is_conversation_member((storage.foldername(name))[1]::uuid)
    AND auth.uid() = owner
  );

-- Add the conversation_participants trigger to automatically add participants
CREATE OR REPLACE FUNCTION add_conversation_participants()
RETURNS TRIGGER AS $$
DECLARE
  director_id UUID;
BEGIN
  -- Get the director_id
  SELECT p.director_id INTO director_id
  FROM profiles p
  WHERE p.id = NEW.mentor_id;
  
  -- Add client as participant
  INSERT INTO conversation_participants (conversation_id, user_id, role)
  VALUES (NEW.id, NEW.client_id, 'client');
  
  -- Add mentor as participant
  INSERT INTO conversation_participants (conversation_id, user_id, role)
  VALUES (NEW.id, NEW.mentor_id, 'mentor');
  
  -- Add director as participant if exists
  IF director_id IS NOT NULL THEN
    INSERT INTO conversation_participants (conversation_id, user_id, role)
    VALUES (NEW.id, director_id, 'training_director');
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER add_conversation_participants_trigger
AFTER INSERT ON conversations
FOR EACH ROW EXECUTE FUNCTION add_conversation_participants();

-- Enable realtime for relevant tables
ALTER PUBLICATION supabase_realtime ADD TABLE audio_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE conversations;
ALTER PUBLICATION supabase_realtime ADD TABLE favorites;
ALTER PUBLICATION supabase_realtime ADD TABLE bookmarks;

-- ===== NEXT SCRIPT =====

-- PROFILES TABLE
CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  role TEXT NOT NULL CHECK (role IN ('client', 'mentor', 'training_director')),
  mentor_id UUID REFERENCES profiles(id),
  director_id UUID REFERENCES profiles(id),
  full_name TEXT NOT NULL,
  avatar_url TEXT
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Profile policies
CREATE POLICY "Users can read all profiles"
  ON profiles FOR SELECT
  USING (true);

CREATE POLICY "Users can update their own profile"
  ON profiles FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- CONVERSATIONS TABLE
CREATE TABLE IF NOT EXISTS conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  client_id UUID NOT NULL REFERENCES profiles(id),
  mentor_id UUID NOT NULL REFERENCES profiles(id)
);

ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;

-- CONVERSATION PARTICIPANTS TABLE
CREATE TABLE IF NOT EXISTS conversation_participants (
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('client', 'mentor', 'training_director')),
  PRIMARY KEY (conversation_id, user_id)
);

ALTER TABLE conversation_participants ENABLE ROW LEVEL SECURITY;

-- Helper function to check if current user is a conversation member
CREATE OR REPLACE FUNCTION is_conversation_member(conv_uuid UUID)
RETURNS BOOLEAN LANGUAGE SQL SECURITY DEFINER AS $$
  SELECT EXISTS(
    SELECT 1 FROM conversation_participants
    WHERE conversation_id = conv_uuid
    AND user_id = auth.uid()
  );
$$;

-- Conversation policies
CREATE POLICY "Users can view conversations they participate in"
  ON conversations FOR SELECT
  USING (
    client_id = auth.uid() 
    OR mentor_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM profiles mentor
      WHERE mentor.id = mentor_id
      AND mentor.director_id = auth.uid()
    )
  );

CREATE POLICY "Clients can create conversations with their mentor"
  ON conversations FOR INSERT
  WITH CHECK (
    client_id = auth.uid()
    OR (
      mentor_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM profiles
        WHERE id = client_id AND mentor_id = auth.uid()
      )
    )
  );

-- Conversation participants policies
CREATE POLICY "Users can view participants of their conversations"
  ON conversation_participants FOR SELECT
  USING (is_conversation_member(conversation_id));

-- AUDIO MESSAGES TABLE
CREATE TABLE IF NOT EXISTS audio_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES profiles(id),
  audio_url TEXT NOT NULL,
  duration NUMERIC NOT NULL,
  text_transcript TEXT
);

ALTER TABLE audio_messages ENABLE ROW LEVEL SECURITY;

-- Audio messages policies
CREATE POLICY "Conversation members can read messages"
  ON audio_messages FOR SELECT
  USING (is_conversation_member(conversation_id));

CREATE POLICY "Conversation members can add messages"
  ON audio_messages FOR INSERT
  WITH CHECK (
    is_conversation_member(conversation_id)
    AND sender_id = auth.uid()
  );

CREATE POLICY "Senders can delete their own messages"
  ON audio_messages FOR DELETE
  USING (sender_id = auth.uid());

-- BOOKMARKS TABLE
CREATE TABLE IF NOT EXISTS bookmarks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  message_id UUID NOT NULL REFERENCES audio_messages(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id),
  timestamp_sec NUMERIC NOT NULL,
  label TEXT NOT NULL
);

ALTER TABLE bookmarks ENABLE ROW LEVEL SECURITY;

-- Bookmarks policies
CREATE POLICY "Users can manage their own bookmarks"
  ON bookmarks FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- FAVORITES TABLE
CREATE TABLE IF NOT EXISTS favorites (
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  message_id UUID REFERENCES audio_messages(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, message_id)
);

ALTER TABLE favorites ENABLE ROW LEVEL SECURITY;

-- Favorites policies
CREATE POLICY "Users can manage their own favorites"
  ON favorites FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- FOLDERS TABLE
CREATE TABLE IF NOT EXISTS folders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  owner_id UUID NOT NULL REFERENCES profiles(id),
  name TEXT NOT NULL
);

ALTER TABLE folders ENABLE ROW LEVEL SECURITY;

-- Folders policies
CREATE POLICY "Users can manage their own folders"
  ON folders FOR ALL
  USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());

-- FOLDER ITEMS TABLE
CREATE TABLE IF NOT EXISTS folder_items (
  folder_id UUID REFERENCES folders(id) ON DELETE CASCADE,
  message_id UUID REFERENCES audio_messages(id) ON DELETE CASCADE,
  added_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (folder_id, message_id)
);

ALTER TABLE folder_items ENABLE ROW LEVEL SECURITY;

-- Folder items policies
CREATE POLICY "Users can manage items in their folders"
  ON folder_items FOR ALL
  USING (
    folder_id IN (SELECT id FROM folders WHERE owner_id = auth.uid())
  )
  WITH CHECK (
    folder_id IN (SELECT id FROM folders WHERE owner_id = auth.uid())
    AND EXISTS (
      SELECT 1 FROM audio_messages m
      WHERE m.id = message_id
      AND is_conversation_member(m.conversation_id)
    )
  );

-- Set up storage bucket for voice messages
INSERT INTO storage.buckets (id, name, public) VALUES ('voices', 'voices', false)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for secure audio file access
CREATE POLICY "Only conversation members can read audio files"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'voices'
    AND is_conversation_member((storage.foldername(name))[1]::uuid)
  );

CREATE POLICY "Only conversation members can upload audio files"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'voices'
    AND is_conversation_member((storage.foldername(name))[1]::uuid)
    AND auth.uid() = owner
  );

-- Add the conversation_participants trigger to automatically add participants
CREATE OR REPLACE FUNCTION add_conversation_participants()
RETURNS TRIGGER AS $$
DECLARE
  director_id UUID;
BEGIN
  -- Get the director_id
  SELECT p.director_id INTO director_id
  FROM profiles p
  WHERE p.id = NEW.mentor_id;
  
  -- Add client as participant
  INSERT INTO conversation_participants (conversation_id, user_id, role)
  VALUES (NEW.id, NEW.client_id, 'client');
  
  -- Add mentor as participant
  INSERT INTO conversation_participants (conversation_id, user_id, role)
  VALUES (NEW.id, NEW.mentor_id, 'mentor');
  
  -- Add director as participant if exists
  IF director_id IS NOT NULL THEN
    INSERT INTO conversation_participants (conversation_id, user_id, role)
    VALUES (NEW.id, director_id, 'training_director');
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER add_conversation_participants_trigger
AFTER INSERT ON conversations
FOR EACH ROW EXECUTE FUNCTION add_conversation_participants();

-- Enable realtime for relevant tables
ALTER PUBLICATION supabase_realtime ADD TABLE audio_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE conversations;
ALTER PUBLICATION supabase_realtime ADD TABLE favorites;
ALTER PUBLICATION supabase_realtime ADD TABLE bookmarks;

-- ===== NEXT SCRIPT =====

/*
  # Add test user account

  Creates a test user account for Dr. Greg Bottaro with training_director role
*/

-- Create the auth user
INSERT INTO auth.users (
  id,
  instance_id,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  confirmation_token,
  email_change,
  email_change_token_new,
  recovery_token
) VALUES (
  gen_random_uuid(),
  '00000000-0000-0000-0000-000000000000',
  'drgreg@catholicpsych.com',
  crypt('password', gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}',
  '{"full_name":"Greg Bottaro"}',
  now(),
  now(),
  '',
  '',
  '',
  ''
) ON CONFLICT (email) DO NOTHING
SELECT id INTO user_id FROM inserted;

-- Create the profile
INSERT INTO profiles (
  id,
  full_name,
  role,
  created_at
)
SELECT 
  id,
  'Greg Bottaro',
  'training_director',
  now()
FROM auth.users
WHERE email = 'drgreg@catholicpsych.com'
ON CONFLICT (id) DO NOTHING;

-- ===== NEXT SCRIPT =====

-- Create the auth user
WITH new_user AS (
  INSERT INTO auth.users (
    instance_id,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    email_change,
    email_change_token_new,
    recovery_token
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    'drgreg@catholicpsych.com',
    crypt('password', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Greg Bottaro"}',
    now(),
    now(),
    '',
    '',
    '',
    ''
  ) ON CONFLICT (email) DO NOTHING
  RETURNING id
)
-- Create the profile
INSERT INTO profiles (
  id,
  full_name,
  role,
  created_at
)
SELECT 
  id,
  'Greg Bottaro',
  'training_director',
  now()
FROM new_user
ON CONFLICT (id) DO NOTHING;

-- ===== NEXT SCRIPT =====

-- Create the auth user
INSERT INTO auth.users (
  instance_id,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  confirmation_token,
  email_change,
  email_change_token_new,
  recovery_token
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  'drgreg@catholicpsych.com',
  crypt('password', gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}',
  '{"full_name":"Greg Bottaro"}',
  now(),
  now(),
  '',
  '',
  '',
  ''
);

-- Create the profile
INSERT INTO profiles (
  id,
  full_name,
  role,
  created_at
)
SELECT 
  id,
  'Greg Bottaro',
  'training_director',
  now()
FROM auth.users
WHERE email = 'drgreg@catholicpsych.com';

-- ===== NEXT SCRIPT =====

-- Create the auth user
INSERT INTO auth.users (
  id,
  instance_id,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  confirmation_token,
  email_change,
  email_change_token_new,
  recovery_token
) VALUES (
  gen_random_uuid(),
  '00000000-0000-0000-0000-000000000000',
  'drgreg@catholicpsych.com',
  crypt('password', gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}',
  '{"full_name":"Greg Bottaro"}',
  now(),
  now(),
  '',
  '',
  '',
  ''
);

-- Create the profile
INSERT INTO profiles (
  id,
  full_name,
  role,
  created_at
)
SELECT 
  id,
  'Greg Bottaro',
  'training_director',
  now()
FROM auth.users
WHERE email = 'drgreg@catholicpsych.com';

-- ===== NEXT SCRIPT =====

/*
  # Clean up test users
  
  Removes any existing test users with the email drgreg@catholicpsych.com
*/

-- Delete the profile first due to foreign key constraints
DELETE FROM profiles
WHERE id IN (
  SELECT id FROM auth.users WHERE email = 'drgreg@catholicpsych.com'
);

-- Then delete the auth user
DELETE FROM auth.users
WHERE email = 'drgreg@catholicpsych.com';

-- ===== NEXT SCRIPT =====

/*
  # Create test user
  
  Creates a test user account for Greg Bottaro as a training director
*/

-- Create the auth user with a specific UUID
WITH new_user AS (
  INSERT INTO auth.users (
    id,
    instance_id,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    email_change,
    email_change_token_new,
    recovery_token,
    aud,
    role
  ) VALUES (
    gen_random_uuid(),
    '00000000-0000-0000-0000-000000000000',
    'drgreg@catholicpsych.com',
    crypt('password', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Greg Bottaro"}',
    now(),
    now(),
    '',
    '',
    '',
    '',
    'authenticated',
    'authenticated'
  )
  RETURNING id
)
-- Create the profile
INSERT INTO profiles (
  id,
  full_name,
  role,
  created_at
)
SELECT 
  id,
  'Greg Bottaro',
  'training_director',
  now()
FROM new_user;

-- ===== NEXT SCRIPT =====

/*
  # Seed Test Data

  1. New Users
    - 3 Training Directors
    - 3 Mentors
    - 4 Clients
  
  2. Relationships
    - Each Training Director supervises 1 Mentor
    - Each Mentor has 1-2 Clients
  
  3. Content
    - Creates conversations between Mentors and Clients
    - Seeds messages in conversations
    - Adds bookmarks and favorites
*/

-- Function to create a test user
CREATE OR REPLACE FUNCTION create_test_user(
  email TEXT,
  password TEXT,
  full_name TEXT,
  role TEXT
) RETURNS UUID AS $$
DECLARE
  user_id UUID;
BEGIN
  -- Create auth user
  INSERT INTO auth.users (
    id,
    instance_id,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    email_change,
    email_change_token_new,
    recovery_token,
    aud,
    role
  ) VALUES (
    gen_random_uuid(),
    '00000000-0000-0000-0000-000000000000',
    email,
    crypt(password, gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    jsonb_build_object('full_name', full_name),
    now(),
    now(),
    '',
    '',
    '',
    '',
    'authenticated',
    'authenticated'
  )
SELECT id INTO user_id FROM inserted;

  -- Create profile
  INSERT INTO profiles (id, full_name, role)
  VALUES (user_id, full_name, role);

  RETURN user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create Training Directors
DO $$
DECLARE
  td1_id UUID := create_test_user('sarah@example.com', 'password123', 'Sarah Johnson', 'training_director');
  td2_id UUID := create_test_user('michael@example.com', 'password123', 'Michael Chen', 'training_director');
  td3_id UUID := create_test_user('emily@example.com', 'password123', 'Emily Rodriguez', 'training_director');
  
  -- Mentors
  mentor1_id UUID := create_test_user('david@example.com', 'password123', 'David Smith', 'mentor');
  mentor2_id UUID := create_test_user('lisa@example.com', 'password123', 'Lisa Brown', 'mentor');
  mentor3_id UUID := create_test_user('james@example.com', 'password123', 'James Wilson', 'mentor');
  
  -- Clients
  client1_id UUID := create_test_user('anna@example.com', 'password123', 'Anna Taylor', 'client');
  client2_id UUID := create_test_user('robert@example.com', 'password123', 'Robert Martinez', 'client');
  client3_id UUID := create_test_user('sophia@example.com', 'password123', 'Sophia Lee', 'client');
  client4_id UUID := create_test_user('marcus@example.com', 'password123', 'Marcus Anderson', 'client');
  
  -- Conversation IDs
  conv1_id UUID;
  conv2_id UUID;
  conv3_id UUID;
  conv4_id UUID;
  
  -- Message IDs
  msg_id UUID;
BEGIN
  -- Assign mentors to directors
  UPDATE profiles SET director_id = td1_id WHERE id = mentor1_id;
  UPDATE profiles SET director_id = td2_id WHERE id = mentor2_id;
  UPDATE profiles SET director_id = td3_id WHERE id = mentor3_id;
  
  -- Assign clients to mentors
  UPDATE profiles SET mentor_id = mentor1_id WHERE id IN (client1_id, client2_id);
  UPDATE profiles SET mentor_id = mentor2_id WHERE id = client3_id;
  UPDATE profiles SET mentor_id = mentor3_id WHERE id = client4_id;
  
  -- Create conversations
  INSERT INTO conversations (id, client_id, mentor_id) VALUES
SELECT id INTO conv1_id FROM inserted;
  INSERT INTO conversations (id, client_id, mentor_id) VALUES
SELECT id INTO conv2_id FROM inserted;
  INSERT INTO conversations (id, client_id, mentor_id) VALUES
SELECT id INTO conv3_id FROM inserted;
  INSERT INTO conversations (id, client_id, mentor_id) VALUES
SELECT id INTO conv4_id FROM inserted;
  
  -- Add messages to conversations
  -- Conversation 1
  INSERT INTO audio_messages (id, conversation_id, sender_id, audio_url, duration, text_transcript)
  VALUES
    (gen_random_uuid(), conv1_id, mentor1_id, conv1_id || '/msg1.mp3', 120, 'Initial session discussion')
SELECT id INTO msg_id FROM inserted;
  
  INSERT INTO bookmarks (message_id, user_id, timestamp_sec, label)
  VALUES (msg_id, client1_id, 45, 'Important point about anxiety');
  
  INSERT INTO favorites (message_id, user_id)
  VALUES (msg_id, client1_id);
  
  -- Conversation 2
  INSERT INTO audio_messages (id, conversation_id, sender_id, audio_url, duration, text_transcript)
  VALUES
    (gen_random_uuid(), conv2_id, client2_id, conv2_id || '/msg1.mp3', 180, 'Weekly progress update'),
    (gen_random_uuid(), conv2_id, mentor1_id, conv2_id || '/msg2.mp3', 240, 'Feedback and next steps');
  
  -- Conversation 3
  INSERT INTO audio_messages (id, conversation_id, sender_id, audio_url, duration, text_transcript)
  VALUES
    (gen_random_uuid(), conv3_id, mentor2_id, conv3_id || '/msg1.mp3', 300, 'Session summary and homework'),
    (gen_random_uuid(), conv3_id, client3_id, conv3_id || '/msg2.mp3', 150, 'Questions about techniques');
  
  -- Conversation 4
  INSERT INTO audio_messages (id, conversation_id, sender_id, audio_url, duration, text_transcript)
  VALUES
    (gen_random_uuid(), conv4_id, client4_id, conv4_id || '/msg1.mp3', 180, 'Initial concerns'),
    (gen_random_uuid(), conv4_id, mentor3_id, conv4_id || '/msg2.mp3', 360, 'Detailed response and plan');
  
  -- Create some folders
  INSERT INTO folders (owner_id, name)
  SELECT id, 'Important Messages'
  FROM profiles
  WHERE role IN ('client', 'mentor', 'training_director');
END $$;

-- ===== NEXT SCRIPT =====

-- Connect mentors to Dr. Greg
UPDATE profiles
SET director_id = (
  SELECT id FROM profiles WHERE full_name = 'Greg Bottaro'
)
WHERE role = 'mentor' AND email IN (
  'david@example.com',
  'lisa@example.com',
  'james@example.com'
);

-- Create conversations between mentors and their clients
WITH greg_mentors AS (
  SELECT p.id as mentor_id, p.full_name as mentor_name, c.id as client_id, c.full_name as client_name
  FROM profiles p
  JOIN profiles c ON c.mentor_id = p.id
  WHERE p.director_id = (SELECT id FROM profiles WHERE full_name = 'Greg Bottaro')
)
INSERT INTO conversations (client_id, mentor_id)
SELECT client_id, mentor_id
FROM greg_mentors;

-- Add some example messages
WITH new_conversations AS (
  SELECT c.id as conv_id, c.client_id, c.mentor_id,
         cl.full_name as client_name, m.full_name as mentor_name
  FROM conversations c
  JOIN profiles cl ON cl.id = c.client_id
  JOIN profiles m ON m.id = c.mentor_id
  WHERE m.director_id = (SELECT id FROM profiles WHERE full_name = 'Greg Bottaro')
)
INSERT INTO audio_messages (conversation_id, sender_id, audio_url, duration, text_transcript)
SELECT 
  nc.conv_id,
  nc.mentor_id,
  nc.conv_id || '/welcome.mp3',
  180,
  'Welcome message from ' || nc.mentor_name || ' to ' || nc.client_name
FROM new_conversations nc;

-- Add some bookmarks and favorites for Dr. Greg
WITH recent_messages AS (
  SELECT am.id as message_id
  FROM audio_messages am
  JOIN conversations c ON c.id = am.conversation_id
  JOIN profiles m ON m.id = c.mentor_id
  WHERE m.director_id = (SELECT id FROM profiles WHERE full_name = 'Greg Bottaro')
  LIMIT 3
)
INSERT INTO bookmarks (message_id, user_id, timestamp_sec, label)
SELECT 
  rm.message_id,
  (SELECT id FROM profiles WHERE full_name = 'Greg Bottaro'),
  60,
  'Important supervision point'
FROM recent_messages rm;

-- Create folders for Dr. Greg
INSERT INTO folders (owner_id, name)
SELECT 
  id,
  name
FROM (
  SELECT 
    (SELECT id FROM profiles WHERE full_name = 'Greg Bottaro') as id,
    unnest(ARRAY[
      'Supervision Notes',
      'Training Materials',
      'Client Progress',
      'Best Practices'
    ]) as name
) folders;

-- ===== NEXT SCRIPT =====

/*
  # Connect test users with Dr. Greg

  1. Updates
    - Connect mentors to Dr. Greg as their training director
    - Create conversations between mentors and their clients
    - Add example welcome messages
    - Create bookmarks for supervision points
    - Set up organizational folders

  2. Security
    - Uses existing RLS policies
    - No direct auth table modifications
*/

-- Connect mentors to Dr. Greg
UPDATE profiles
SET director_id = (
  SELECT id FROM profiles WHERE full_name = 'Greg Bottaro'
)
WHERE role = 'mentor' AND full_name IN (
  'David Smith',
  'Lisa Brown',
  'James Wilson'
);

-- Create conversations between mentors and their clients
WITH greg_mentors AS (
  SELECT p.id as mentor_id, p.full_name as mentor_name, c.id as client_id, c.full_name as client_name
  FROM profiles p
  JOIN profiles c ON c.mentor_id = p.id
  WHERE p.director_id = (SELECT id FROM profiles WHERE full_name = 'Greg Bottaro')
)
INSERT INTO conversations (client_id, mentor_id)
SELECT client_id, mentor_id
FROM greg_mentors;

-- Add some example messages
WITH new_conversations AS (
  SELECT c.id as conv_id, c.client_id, c.mentor_id,
         cl.full_name as client_name, m.full_name as mentor_name
  FROM conversations c
  JOIN profiles cl ON cl.id = c.client_id
  JOIN profiles m ON m.id = c.mentor_id
  WHERE m.director_id = (SELECT id FROM profiles WHERE full_name = 'Greg Bottaro')
)
INSERT INTO audio_messages (conversation_id, sender_id, audio_url, duration, text_transcript)
SELECT 
  nc.conv_id,
  nc.mentor_id,
  nc.conv_id || '/welcome.mp3',
  180,
  'Welcome message from ' || nc.mentor_name || ' to ' || nc.client_name
FROM new_conversations nc;

-- Add some bookmarks and favorites for Dr. Greg
WITH recent_messages AS (
  SELECT am.id as message_id
  FROM audio_messages am
  JOIN conversations c ON c.id = am.conversation_id
  JOIN profiles m ON m.id = c.mentor_id
  WHERE m.director_id = (SELECT id FROM profiles WHERE full_name = 'Greg Bottaro')
  LIMIT 3
)
INSERT INTO bookmarks (message_id, user_id, timestamp_sec, label)
SELECT 
  rm.message_id,
  (SELECT id FROM profiles WHERE full_name = 'Greg Bottaro'),
  60,
  'Important supervision point'
FROM recent_messages rm;

-- Create folders for Dr. Greg
INSERT INTO folders (owner_id, name)
SELECT 
  id,
  name
FROM (
  SELECT 
    (SELECT id FROM profiles WHERE full_name = 'Greg Bottaro') as id,
    unnest(ARRAY[
      'Supervision Notes',
      'Training Materials',
      'Client Progress',
      'Best Practices'
    ]) as name
) folders;

-- ===== NEXT SCRIPT =====

/*
  # Fix conversation access for Dr. Greg

  This migration ensures Dr. Greg has proper access to all conversations
  by adding him as a participant to relevant conversations.
*/

-- Add Dr. Greg as a participant to all conversations where he's the director
INSERT INTO conversation_participants (conversation_id, user_id, role)
SELECT DISTINCT c.id, p.id, 'training_director'
FROM conversations c
JOIN profiles m ON m.id = c.mentor_id
JOIN profiles p ON p.full_name = 'Greg Bottaro'
WHERE m.director_id = p.id
ON CONFLICT (conversation_id, user_id) DO NOTHING;

-- Ensure all conversations have the correct participants
INSERT INTO conversation_participants (conversation_id, user_id, role)
SELECT c.id, c.client_id, 'client'
FROM conversations c
WHERE NOT EXISTS (
  SELECT 1 FROM conversation_participants cp
  WHERE cp.conversation_id = c.id AND cp.user_id = c.client_id
);

INSERT INTO conversation_participants (conversation_id, user_id, role)
SELECT c.id, c.mentor_id, 'mentor'
FROM conversations c
WHERE NOT EXISTS (
  SELECT 1 FROM conversation_participants cp
  WHERE cp.conversation_id = c.id AND cp.user_id = c.mentor_id
);

-- ===== NEXT SCRIPT =====

/*
  # Initial Schema Setup

  1. Tables
    - profiles (user profiles with role-based relationships)
    - conversations (chat sessions between clients and mentors)
    - conversation_participants (tracks who is in each conversation)
    - audio_messages (voice messages in conversations)
    - bookmarks (saved timestamps in audio messages)
    - favorites (favorite messages)
    - folders (message organization)
    - folder_items (messages in folders)

  2. Security
    - Row Level Security (RLS) enabled on all tables
    - Policies for data access control
    - Storage policies for audio files

  3. Functions and Triggers
    - is_conversation_member() helper function
    - add_conversation_participants() trigger function
*/

-- Helper function to check if current user is a conversation member
CREATE OR REPLACE FUNCTION is_conversation_member(conv_uuid UUID)
RETURNS BOOLEAN LANGUAGE SQL SECURITY DEFINER AS $$
  SELECT EXISTS(
    SELECT 1 FROM conversation_participants
    WHERE conversation_id = conv_uuid
    AND user_id = auth.uid()
  );
$$;

-- PROFILES TABLE
CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  role TEXT NOT NULL CHECK (role IN ('client', 'mentor', 'training_director')),
  mentor_id UUID REFERENCES profiles(id),
  director_id UUID REFERENCES profiles(id),
  full_name TEXT NOT NULL,
  avatar_url TEXT
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Profile policies
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'profiles' AND policyname = 'Users can read all profiles'
  ) THEN
    CREATE POLICY "Users can read all profiles"
      ON profiles FOR SELECT
      USING (true);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'profiles' AND policyname = 'Users can update their own profile'
  ) THEN
    CREATE POLICY "Users can update their own profile"
      ON profiles FOR UPDATE
      USING (id = auth.uid())
      WITH CHECK (id = auth.uid());
  END IF;
END $$;

-- CONVERSATIONS TABLE
CREATE TABLE IF NOT EXISTS conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  client_id UUID NOT NULL REFERENCES profiles(id),
  mentor_id UUID NOT NULL REFERENCES profiles(id)
);

ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;

-- CONVERSATION PARTICIPANTS TABLE
CREATE TABLE IF NOT EXISTS conversation_participants (
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('client', 'mentor', 'training_director')),
  PRIMARY KEY (conversation_id, user_id)
);

ALTER TABLE conversation_participants ENABLE ROW LEVEL SECURITY;

-- Conversation policies
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'conversations' AND policyname = 'Users can view conversations they participate in'
  ) THEN
    CREATE POLICY "Users can view conversations they participate in"
      ON conversations FOR SELECT
      USING (
        client_id = auth.uid() 
        OR mentor_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM profiles mentor
          WHERE mentor.id = mentor_id
          AND mentor.director_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'conversations' AND policyname = 'Clients can create conversations with their mentor'
  ) THEN
    CREATE POLICY "Clients can create conversations with their mentor"
      ON conversations FOR INSERT
      WITH CHECK (
        client_id = auth.uid()
        OR (
          mentor_id = auth.uid()
          OR EXISTS (
            SELECT 1 FROM profiles
            WHERE id = client_id AND mentor_id = auth.uid()
          )
        )
      );
  END IF;
END $$;

-- Conversation participants policies
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'conversation_participants' AND policyname = 'Users can view participants of their conversations'
  ) THEN
    CREATE POLICY "Users can view participants of their conversations"
      ON conversation_participants FOR SELECT
      USING (is_conversation_member(conversation_id));
  END IF;
END $$;

-- AUDIO MESSAGES TABLE
CREATE TABLE IF NOT EXISTS audio_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES profiles(id),
  audio_url TEXT NOT NULL,
  duration NUMERIC NOT NULL,
  text_transcript TEXT
);

ALTER TABLE audio_messages ENABLE ROW LEVEL SECURITY;

-- Audio messages policies
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'audio_messages' AND policyname = 'Conversation members can read messages'
  ) THEN
    CREATE POLICY "Conversation members can read messages"
      ON audio_messages FOR SELECT
      USING (is_conversation_member(conversation_id));
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'audio_messages' AND policyname = 'Conversation members can add messages'
  ) THEN
    CREATE POLICY "Conversation members can add messages"
      ON audio_messages FOR INSERT
      WITH CHECK (
        is_conversation_member(conversation_id)
        AND sender_id = auth.uid()
      );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'audio_messages' AND policyname = 'Senders can delete their own messages'
  ) THEN
    CREATE POLICY "Senders can delete their own messages"
      ON audio_messages FOR DELETE
      USING (sender_id = auth.uid());
  END IF;
END $$;

-- BOOKMARKS TABLE
CREATE TABLE IF NOT EXISTS bookmarks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  message_id UUID NOT NULL REFERENCES audio_messages(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id),
  timestamp_sec NUMERIC NOT NULL,
  label TEXT NOT NULL
);

ALTER TABLE bookmarks ENABLE ROW LEVEL SECURITY;

-- Bookmarks policies
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'bookmarks' AND policyname = 'Users can manage their own bookmarks'
  ) THEN
    CREATE POLICY "Users can manage their own bookmarks"
      ON bookmarks FOR ALL
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

-- FAVORITES TABLE
CREATE TABLE IF NOT EXISTS favorites (
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  message_id UUID REFERENCES audio_messages(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, message_id)
);

ALTER TABLE favorites ENABLE ROW LEVEL SECURITY;

-- Favorites policies
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'favorites' AND policyname = 'Users can manage their own favorites'
  ) THEN
    CREATE POLICY "Users can manage their own favorites"
      ON favorites FOR ALL
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

-- FOLDERS TABLE
CREATE TABLE IF NOT EXISTS folders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  owner_id UUID NOT NULL REFERENCES profiles(id),
  name TEXT NOT NULL
);

ALTER TABLE folders ENABLE ROW LEVEL SECURITY;

-- Folders policies
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'folders' AND policyname = 'Users can manage their own folders'
  ) THEN
    CREATE POLICY "Users can manage their own folders"
      ON folders FOR ALL
      USING (owner_id = auth.uid())
      WITH CHECK (owner_id = auth.uid());
  END IF;
END $$;

-- FOLDER ITEMS TABLE
CREATE TABLE IF NOT EXISTS folder_items (
  folder_id UUID REFERENCES folders(id) ON DELETE CASCADE,
  message_id UUID REFERENCES audio_messages(id) ON DELETE CASCADE,
  added_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (folder_id, message_id)
);

ALTER TABLE folder_items ENABLE ROW LEVEL SECURITY;

-- Folder items policies
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'folder_items' AND policyname = 'Users can manage items in their folders'
  ) THEN
    CREATE POLICY "Users can manage items in their folders"
      ON folder_items FOR ALL
      USING (
        folder_id IN (SELECT id FROM folders WHERE owner_id = auth.uid())
      )
      WITH CHECK (
        folder_id IN (SELECT id FROM folders WHERE owner_id = auth.uid())
        AND EXISTS (
          SELECT 1 FROM audio_messages m
          WHERE m.id = message_id
          AND is_conversation_member(m.conversation_id)
        )
      );
  END IF;
END $$;

-- Set up storage bucket for voice messages
INSERT INTO storage.buckets (id, name, public) VALUES ('voices', 'voices', false)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for secure audio file access
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'objects' AND schemaname = 'storage' AND policyname = 'Only conversation members can read audio files'
  ) THEN
    CREATE POLICY "Only conversation members can read audio files"
      ON storage.objects FOR SELECT
      USING (
        bucket_id = 'voices'
        AND is_conversation_member((storage.foldername(name))[1]::uuid)
      );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'objects' AND schemaname = 'storage' AND policyname = 'Only conversation members can upload audio files'
  ) THEN
    CREATE POLICY "Only conversation members can upload audio files"
      ON storage.objects FOR INSERT
      WITH CHECK (
        bucket_id = 'voices'
        AND is_conversation_member((storage.foldername(name))[1]::uuid)
        AND auth.uid() = owner
      );
  END IF;
END $$;

-- Add the conversation_participants trigger to automatically add participants
CREATE OR REPLACE FUNCTION add_conversation_participants()
RETURNS TRIGGER AS $$
DECLARE
  director_id UUID;
BEGIN
  -- Get the director_id
  SELECT p.director_id INTO director_id
  FROM profiles p
  WHERE p.id = NEW.mentor_id;
  
  -- Add client as participant
  INSERT INTO conversation_participants (conversation_id, user_id, role)
  VALUES (NEW.id, NEW.client_id, 'client');
  
  -- Add mentor as participant
  INSERT INTO conversation_participants (conversation_id, user_id, role)
  VALUES (NEW.id, NEW.mentor_id, 'mentor');
  
  -- Add director as participant if exists
  IF director_id IS NOT NULL THEN
    INSERT INTO conversation_participants (conversation_id, user_id, role)
    VALUES (NEW.id, director_id, 'training_director');
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS add_conversation_participants_trigger ON conversations;
CREATE TRIGGER add_conversation_participants_trigger
AFTER INSERT ON conversations
FOR EACH ROW EXECUTE FUNCTION add_conversation_participants();

-- Enable realtime for relevant tables
ALTER PUBLICATION supabase_realtime ADD TABLE audio_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE conversations;
ALTER PUBLICATION supabase_realtime ADD TABLE favorites;
ALTER PUBLICATION supabase_realtime ADD TABLE bookmarks;

-- ===== NEXT SCRIPT =====

/*
  # Create initial training director user
  
  Creates the initial training director user account and profile for Dr. Greg Bottaro.
  
  1. Creates auth user with email and password
  2. Creates corresponding profile with training director role
*/

DO $$
DECLARE
  user_id UUID;
BEGIN
  -- Create the auth user
  INSERT INTO auth.users (
    instance_id,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    email_change,
    email_change_token_new,
    recovery_token
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    'drgreg@catholicpsych.com',
    crypt('password', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Greg Bottaro"}',
    now(),
    now(),
    '',
    '',
    '',
    ''
  )
  ON CONFLICT (email) DO NOTHING
SELECT id INTO user_id FROM inserted;

  -- Create the profile if user was created
  IF user_id IS NOT NULL THEN
    INSERT INTO profiles (
      id,
      full_name,
      role,
      created_at
    ) VALUES (
      user_id,
      'Greg Bottaro',
      'training_director',
      now()
    )
    ON CONFLICT (id) DO NOTHING;
  END IF;
END $$;

-- ===== NEXT SCRIPT =====

/*
  # Initial Schema Setup

  1. Tables
    - profiles
    - conversations
    - conversation_participants
    - audio_messages
    - bookmarks
    - favorites
    - folders
    - folder_items

  2. Functions
    - is_conversation_member
    - add_conversation_participants

  3. Policies
    - Row Level Security for all tables
    - Access control policies for each table
    - Storage policies for audio files

  4. Storage
    - Voice messages bucket setup
*/

-- Helper function to check if current user is a conversation member
CREATE OR REPLACE FUNCTION is_conversation_member(conv_uuid UUID)
RETURNS BOOLEAN LANGUAGE SQL SECURITY DEFINER AS $$
  SELECT EXISTS(
    SELECT 1 FROM conversation_participants
    WHERE conversation_id = conv_uuid
    AND user_id = auth.uid()
  );
$$;

-- PROFILES TABLE
CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  role TEXT NOT NULL CHECK (role IN ('client', 'mentor', 'training_director')),
  mentor_id UUID REFERENCES profiles(id),
  director_id UUID REFERENCES profiles(id),
  full_name TEXT NOT NULL,
  avatar_url TEXT
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Profile policies
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'profiles' AND policyname = 'Users can read all profiles'
  ) THEN
    CREATE POLICY "Users can read all profiles"
      ON profiles FOR SELECT
      USING (true);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'profiles' AND policyname = 'Users can update their own profile'
  ) THEN
    CREATE POLICY "Users can update their own profile"
      ON profiles FOR UPDATE
      USING (id = auth.uid())
      WITH CHECK (id = auth.uid());
  END IF;
END $$;

-- CONVERSATIONS TABLE
CREATE TABLE IF NOT EXISTS conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  client_id UUID NOT NULL REFERENCES profiles(id),
  mentor_id UUID NOT NULL REFERENCES profiles(id)
);

ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;

-- CONVERSATION PARTICIPANTS TABLE
CREATE TABLE IF NOT EXISTS conversation_participants (
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('client', 'mentor', 'training_director')),
  PRIMARY KEY (conversation_id, user_id)
);

ALTER TABLE conversation_participants ENABLE ROW LEVEL SECURITY;

-- Conversation policies
CREATE POLICY "Users can view conversations they participate in"
  ON conversations FOR SELECT
  USING (
    client_id = auth.uid() 
    OR mentor_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM profiles mentor
      WHERE mentor.id = mentor_id
      AND mentor.director_id = auth.uid()
    )
  );

CREATE POLICY "Clients can create conversations with their mentor"
  ON conversations FOR INSERT
  WITH CHECK (
    client_id = auth.uid()
    OR (
      mentor_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM profiles
        WHERE id = client_id AND mentor_id = auth.uid()
      )
    )
  );

-- Conversation participants policies
CREATE POLICY "Users can view participants of their conversations"
  ON conversation_participants FOR SELECT
  USING (is_conversation_member(conversation_id));

-- AUDIO MESSAGES TABLE
CREATE TABLE IF NOT EXISTS audio_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES profiles(id),
  audio_url TEXT NOT NULL,
  duration NUMERIC NOT NULL,
  text_transcript TEXT
);

ALTER TABLE audio_messages ENABLE ROW LEVEL SECURITY;

-- Audio messages policies
CREATE POLICY "Conversation members can read messages"
  ON audio_messages FOR SELECT
  USING (is_conversation_member(conversation_id));

CREATE POLICY "Conversation members can add messages"
  ON audio_messages FOR INSERT
  WITH CHECK (
    is_conversation_member(conversation_id)
    AND sender_id = auth.uid()
  );

CREATE POLICY "Senders can delete their own messages"
  ON audio_messages FOR DELETE
  USING (sender_id = auth.uid());

-- BOOKMARKS TABLE
CREATE TABLE IF NOT EXISTS bookmarks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  message_id UUID NOT NULL REFERENCES audio_messages(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id),
  timestamp_sec NUMERIC NOT NULL,
  label TEXT NOT NULL
);

ALTER TABLE bookmarks ENABLE ROW LEVEL SECURITY;

-- Bookmarks policies
CREATE POLICY "Users can manage their own bookmarks"
  ON bookmarks FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- FAVORITES TABLE
CREATE TABLE IF NOT EXISTS favorites (
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  message_id UUID REFERENCES audio_messages(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, message_id)
);

ALTER TABLE favorites ENABLE ROW LEVEL SECURITY;

-- Favorites policies
CREATE POLICY "Users can manage their own favorites"
  ON favorites FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- FOLDERS TABLE
CREATE TABLE IF NOT EXISTS folders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  owner_id UUID NOT NULL REFERENCES profiles(id),
  name TEXT NOT NULL
);

ALTER TABLE folders ENABLE ROW LEVEL SECURITY;

-- Folders policies
CREATE POLICY "Users can manage their own folders"
  ON folders FOR ALL
  USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());

-- FOLDER ITEMS TABLE
CREATE TABLE IF NOT EXISTS folder_items (
  folder_id UUID REFERENCES folders(id) ON DELETE CASCADE,
  message_id UUID REFERENCES audio_messages(id) ON DELETE CASCADE,
  added_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (folder_id, message_id)
);

ALTER TABLE folder_items ENABLE ROW LEVEL SECURITY;

-- Folder items policies
CREATE POLICY "Users can manage items in their folders"
  ON folder_items FOR ALL
  USING (
    folder_id IN (SELECT id FROM folders WHERE owner_id = auth.uid())
  )
  WITH CHECK (
    folder_id IN (SELECT id FROM folders WHERE owner_id = auth.uid())
    AND EXISTS (
      SELECT 1 FROM audio_messages m
      WHERE m.id = message_id
      AND is_conversation_member(m.conversation_id)
    )
  );

-- Set up storage bucket for voice messages
INSERT INTO storage.buckets (id, name, public) VALUES ('voices', 'voices', false)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for secure audio file access
CREATE POLICY "Only conversation members can read audio files"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'voices'
    AND is_conversation_member((storage.foldername(name))[1]::uuid)
  );

CREATE POLICY "Only conversation members can upload audio files"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'voices'
    AND is_conversation_member((storage.foldername(name))[1]::uuid)
    AND auth.uid() = owner
  );

-- Add the conversation_participants trigger to automatically add participants
CREATE OR REPLACE FUNCTION add_conversation_participants()
RETURNS TRIGGER AS $$
DECLARE
  director_id UUID;
BEGIN
  -- Get the director_id
  SELECT p.director_id INTO director_id
  FROM profiles p
  WHERE p.id = NEW.mentor_id;
  
  -- Add client as participant
  INSERT INTO conversation_participants (conversation_id, user_id, role)
  VALUES (NEW.id, NEW.client_id, 'client');
  
  -- Add mentor as participant
  INSERT INTO conversation_participants (conversation_id, user_id, role)
  VALUES (NEW.id, NEW.mentor_id, 'mentor');
  
  -- Add director as participant if exists
  IF director_id IS NOT NULL THEN
    INSERT INTO conversation_participants (conversation_id, user_id, role)
    VALUES (NEW.id, director_id, 'training_director');
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER add_conversation_participants_trigger
AFTER INSERT ON conversations
FOR EACH ROW EXECUTE FUNCTION add_conversation_participants();

-- Enable realtime for relevant tables
ALTER PUBLICATION supabase_realtime ADD TABLE audio_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE conversations;
ALTER PUBLICATION supabase_realtime ADD TABLE favorites;
ALTER PUBLICATION supabase_realtime ADD TABLE bookmarks;

-- ===== NEXT SCRIPT =====

/*
  # Create Initial Training Director

  1. Create auth user for Dr. Greg Bottaro
  2. Create corresponding profile record
*/

DO $$ 
DECLARE
  user_id UUID;
BEGIN
  -- Create the auth user
  INSERT INTO auth.users (
    instance_id,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    email_change,
    email_change_token_new,
    recovery_token
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    'drgreg@catholicpsych.com',
    crypt('password', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Greg Bottaro"}',
    now(),
    now(),
    '',
    '',
    '',
    ''
  )
SELECT id INTO user_id FROM inserted;

  -- Create the profile
  IF user_id IS NOT NULL THEN
    INSERT INTO profiles (
      id,
      full_name,
      role,
      created_at
    ) VALUES (
      user_id,
      'Greg Bottaro',
      'training_director',
      now()
    );
  END IF;
END $$;

-- ===== NEXT SCRIPT =====

/*
  # Create Initial Training Director (Alternative Approach)

  1. Create auth user for Dr. Greg Bottaro with explicit ID
  2. Create corresponding profile record
*/

DO $$ 
DECLARE
  new_user_id UUID := gen_random_uuid();
BEGIN
  -- Create the auth user with explicit ID
  INSERT INTO auth.users (
    id,
    instance_id,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    email_change,
    email_change_token_new,
    recovery_token
  ) VALUES (
    new_user_id,
    '00000000-0000-0000-0000-000000000000',
    'drgreg@catholicpsych.com',
    crypt('password', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Greg Bottaro"}',
    now(),
    now(),
    '',
    '',
    '',
    ''
  );

  -- Create the profile
  INSERT INTO profiles (
    id,
    full_name,
    role,
    created_at
  ) VALUES (
    new_user_id,
    'Greg Bottaro',
    'training_director',
    now()
  );
END $$;

-- ===== NEXT SCRIPT =====

/*
  # Create Initial Training Director (Final Approach)

  1. Create auth user for Dr. Greg Bottaro with explicit ID
  2. Create corresponding profile record
*/

DO $$ 
DECLARE
  new_user_id UUID := gen_random_uuid();
BEGIN
  -- Create the auth user with explicit ID
  INSERT INTO auth.users (
    id,
    instance_id,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    email_change,
    email_change_token_new,
    recovery_token
  ) VALUES (
    new_user_id,
    '00000000-0000-0000-0000-000000000000',
    'drgreg@catholicpsych.com',
    crypt('password', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Greg Bottaro"}',
    now(),
    now(),
    '',
    '',
    '',
    ''
  );

  -- Create the profile
  INSERT INTO profiles (
    id,
    full_name,
    role,
    created_at
  ) VALUES (
    new_user_id,
    'Greg Bottaro',
    'training_director',
    now()
  );
END $$;

-- ===== NEXT SCRIPT =====

/*
  # Update conversation policy

  1. Changes
    - Drop existing conversation policy for viewing conversations
    - Create new policy using conversation_participants table for access control
  
  2. Security
    - Ensures users can only view conversations they are participants in
    - Uses the conversation_participants table for more granular access control
*/

-- Drop the existing policy
DROP POLICY IF EXISTS "Users can view conversations they participate in" ON conversations;

-- Create the new policy using conversation_participants table
CREATE POLICY "Users can view conversations they participate in"
ON conversations
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM conversation_participants
    WHERE conversation_participants.conversation_id = conversations.id
    AND conversation_participants.user_id = auth.uid()
  )
);

-- ===== NEXT SCRIPT =====

/*
  # Schema update for tiered voice messaging platform

  1. Tables
    - `profiles`: User profiles with role-based relationships
    - `conversations`: Voice message conversations between clients and mentors
    - `conversation_participants`: Tracks participants in each conversation
    - `audio_messages`: Stores voice messages with transcripts
    - `bookmarks`: Message bookmarks with timestamps
    - `favorites`: User's favorite messages
    - `folders`: User-created message collections
    - `folder_items`: Messages organized in folders

  2. Security
    - Row Level Security (RLS) enabled on all tables
    - Role-based access control
    - Secure file storage for voice messages
    - Conversation member validation

  3. Features
    - Real-time updates for messages and conversations
    - Automatic participant management
    - Hierarchical relationships (client -> mentor -> director)
    - Message organization (bookmarks, favorites, folders)
*/

-- Helper function to check if current user is a conversation member
CREATE OR REPLACE FUNCTION is_conversation_member(conv_uuid UUID)
RETURNS BOOLEAN LANGUAGE SQL SECURITY DEFINER AS $$
  SELECT EXISTS(
    SELECT 1 FROM conversation_participants
    WHERE conversation_id = conv_uuid
    AND user_id = auth.uid()
  );
$$;

-- PROFILES TABLE
CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  role TEXT NOT NULL CHECK (role IN ('client', 'mentor', 'training_director')),
  mentor_id UUID REFERENCES profiles(id),
  director_id UUID REFERENCES profiles(id),
  full_name TEXT NOT NULL,
  avatar_url TEXT
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Profile policies
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'profiles' AND policyname = 'Users can read all profiles'
  ) THEN
    CREATE POLICY "Users can read all profiles"
      ON profiles FOR SELECT
      USING (true);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'profiles' AND policyname = 'Users can update their own profile'
  ) THEN
    CREATE POLICY "Users can update their own profile"
      ON profiles FOR UPDATE
      USING (id = auth.uid())
      WITH CHECK (id = auth.uid());
  END IF;
END $$;

-- CONVERSATIONS TABLE
CREATE TABLE IF NOT EXISTS conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  client_id UUID NOT NULL REFERENCES profiles(id),
  mentor_id UUID NOT NULL REFERENCES profiles(id)
);

ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;

-- CONVERSATION PARTICIPANTS TABLE
CREATE TABLE IF NOT EXISTS conversation_participants (
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('client', 'mentor', 'training_director')),
  PRIMARY KEY (conversation_id, user_id)
);

ALTER TABLE conversation_participants ENABLE ROW LEVEL SECURITY;

-- Conversation policies
DO $$ BEGIN
  DROP POLICY IF EXISTS "Users can view conversations they participate in" ON conversations;
  
  CREATE POLICY "Users can view conversations they participate in"
    ON conversations FOR SELECT
    USING (
      EXISTS (
        SELECT 1 FROM conversation_participants
        WHERE conversation_participants.conversation_id = conversations.id
        AND conversation_participants.user_id = auth.uid()
      )
    );
END $$;

CREATE POLICY "Clients can create conversations with their mentor"
  ON conversations FOR INSERT
  WITH CHECK (
    client_id = auth.uid()
    OR (
      mentor_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM profiles
        WHERE id = client_id AND mentor_id = auth.uid()
      )
    )
  );

-- Conversation participants policies
CREATE POLICY "Users can view participants of their conversations"
  ON conversation_participants FOR SELECT
  USING (is_conversation_member(conversation_id));

-- AUDIO MESSAGES TABLE
CREATE TABLE IF NOT EXISTS audio_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES profiles(id),
  audio_url TEXT NOT NULL,
  duration NUMERIC NOT NULL,
  text_transcript TEXT
);

ALTER TABLE audio_messages ENABLE ROW LEVEL SECURITY;

-- Audio messages policies
CREATE POLICY "Conversation members can read messages"
  ON audio_messages FOR SELECT
  USING (is_conversation_member(conversation_id));

CREATE POLICY "Conversation members can add messages"
  ON audio_messages FOR INSERT
  WITH CHECK (
    is_conversation_member(conversation_id)
    AND sender_id = auth.uid()
  );

CREATE POLICY "Senders can delete their own messages"
  ON audio_messages FOR DELETE
  USING (sender_id = auth.uid());

-- BOOKMARKS TABLE
CREATE TABLE IF NOT EXISTS bookmarks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  message_id UUID NOT NULL REFERENCES audio_messages(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id),
  timestamp_sec NUMERIC NOT NULL,
  label TEXT NOT NULL
);

ALTER TABLE bookmarks ENABLE ROW LEVEL SECURITY;

-- Bookmarks policies
CREATE POLICY "Users can manage their own bookmarks"
  ON bookmarks FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- FAVORITES TABLE
CREATE TABLE IF NOT EXISTS favorites (
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  message_id UUID REFERENCES audio_messages(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, message_id)
);

ALTER TABLE favorites ENABLE ROW LEVEL SECURITY;

-- Favorites policies
CREATE POLICY "Users can manage their own favorites"
  ON favorites FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- FOLDERS TABLE
CREATE TABLE IF NOT EXISTS folders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  owner_id UUID NOT NULL REFERENCES profiles(id),
  name TEXT NOT NULL
);

ALTER TABLE folders ENABLE ROW LEVEL SECURITY;

-- Folders policies
CREATE POLICY "Users can manage their own folders"
  ON folders FOR ALL
  USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());

-- FOLDER ITEMS TABLE
CREATE TABLE IF NOT EXISTS folder_items (
  folder_id UUID REFERENCES folders(id) ON DELETE CASCADE,
  message_id UUID REFERENCES audio_messages(id) ON DELETE CASCADE,
  added_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (folder_id, message_id)
);

ALTER TABLE folder_items ENABLE ROW LEVEL SECURITY;

-- Folder items policies
CREATE POLICY "Users can manage items in their folders"
  ON folder_items FOR ALL
  USING (
    folder_id IN (SELECT id FROM folders WHERE owner_id = auth.uid())
  )
  WITH CHECK (
    folder_id IN (SELECT id FROM folders WHERE owner_id = auth.uid())
    AND EXISTS (
      SELECT 1 FROM audio_messages m
      WHERE m.id = message_id
      AND is_conversation_member(m.conversation_id)
    )
  );

-- Set up storage bucket for voice messages
INSERT INTO storage.buckets (id, name, public) VALUES ('voices', 'voices', false)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for secure audio file access
CREATE POLICY "Only conversation members can read audio files"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'voices'
    AND is_conversation_member((storage.foldername(name))[1]::uuid)
  );

CREATE POLICY "Only conversation members can upload audio files"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'voices'
    AND is_conversation_member((storage.foldername(name))[1]::uuid)
    AND auth.uid() = owner
  );

-- Add the conversation_participants trigger to automatically add participants
CREATE OR REPLACE FUNCTION add_conversation_participants()
RETURNS TRIGGER AS $$
DECLARE
  director_id UUID;
BEGIN
  -- Get the director_id
  SELECT p.director_id INTO director_id
  FROM profiles p
  WHERE p.id = NEW.mentor_id;
  
  -- Add client as participant
  INSERT INTO conversation_participants (conversation_id, user_id, role)
  VALUES (NEW.id, NEW.client_id, 'client');
  
  -- Add mentor as participant
  INSERT INTO conversation_participants (conversation_id, user_id, role)
  VALUES (NEW.id, NEW.mentor_id, 'mentor');
  
  -- Add director as participant if exists
  IF director_id IS NOT NULL THEN
    INSERT INTO conversation_participants (conversation_id, user_id, role)
    VALUES (NEW.id, director_id, 'training_director');
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER add_conversation_participants_trigger
AFTER INSERT ON conversations
FOR EACH ROW EXECUTE FUNCTION add_conversation_participants();

-- Enable realtime for relevant tables
ALTER PUBLICATION supabase_realtime ADD TABLE audio_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE conversations;
ALTER PUBLICATION supabase_realtime ADD TABLE favorites;
ALTER PUBLICATION supabase_realtime ADD TABLE bookmarks;