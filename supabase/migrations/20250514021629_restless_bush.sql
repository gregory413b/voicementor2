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