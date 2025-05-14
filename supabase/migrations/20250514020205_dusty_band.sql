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