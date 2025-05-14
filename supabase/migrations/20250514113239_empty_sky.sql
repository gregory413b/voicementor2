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