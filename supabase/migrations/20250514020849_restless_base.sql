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
  RETURNING id INTO user_id;

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
    (gen_random_uuid(), client1_id, mentor1_id) RETURNING id INTO conv1_id;
  INSERT INTO conversations (id, client_id, mentor_id) VALUES
    (gen_random_uuid(), client2_id, mentor1_id) RETURNING id INTO conv2_id;
  INSERT INTO conversations (id, client_id, mentor_id) VALUES
    (gen_random_uuid(), client3_id, mentor2_id) RETURNING id INTO conv3_id;
  INSERT INTO conversations (id, client_id, mentor_id) VALUES
    (gen_random_uuid(), client4_id, mentor3_id) RETURNING id INTO conv4_id;
  
  -- Add messages to conversations
  -- Conversation 1
  INSERT INTO audio_messages (id, conversation_id, sender_id, audio_url, duration, text_transcript)
  VALUES
    (gen_random_uuid(), conv1_id, mentor1_id, conv1_id || '/msg1.mp3', 120, 'Initial session discussion')
  RETURNING id INTO msg_id;
  
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