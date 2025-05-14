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