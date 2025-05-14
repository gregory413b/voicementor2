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
RETURNING id INTO user_id;

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