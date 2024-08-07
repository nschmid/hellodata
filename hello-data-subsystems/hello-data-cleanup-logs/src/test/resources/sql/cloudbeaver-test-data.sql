--
-- Copyright © 2024, Kanton Bern
-- All rights reserved.
--
-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions are met:
--     * Redistributions of source code must retain the above copyright
--       notice, this list of conditions and the following disclaimer.
--     * Redistributions in binary form must reproduce the above copyright
--       notice, this list of conditions and the following disclaimer in the
--       documentation and/or other materials provided with the distribution.
--     * Neither the name of the <organization> nor the
--       names of its contributors may be used to endorse or promote products
--       derived from this software without specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
-- ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
-- WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
-- DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
-- DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
-- (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
-- LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
-- ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
-- (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
-- SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--


INSERT INTO cloudbeaver.cb_session (session_id, app_session_id, user_id, create_time, last_access_remote_address, last_access_user_agent, last_access_time, last_access_instance_id,
                                    session_type)
VALUES ('e9506d01-2b01-42e1-a0df-6f9c4d9f4597', '1qu0mwtfu2lnct7u7kxqvw25k3', 'admin@hellodata.ch', '2023-11-08 11:18:02.641', '10.0.23.127',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36 Edg/117.0.2045.60', '2023-11-08 13:23:02.637',
        '6E6BFE36FE85:D119RPOBSBJKST-R:XXXXXX', 'CloudBeaver'),
       ('f0a0748b-40e9-4836-9bb9-35871b290f42', '1qu0mwtfu2lnct7u7kxqvw25k3', 'admin@hellodata.ch', '2023-11-08 11:18:02.641', '10.0.23.127',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36 Edg/117.0.2045.60', '2023-11-08 13:23:02.637',
        '6E6BFE36FE85:D119RPOBSBJKST-R:XXXXXX', 'CloudBeaver'),
       ('ada57dc4-6e69-4123-a7b5-a4f0112af3de', '1dg7lgksjjx7p1f8hstc6atude2', 'admin@hellodata.ch', '2023-11-08 11:04:50.208', '10.0.23.127',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36 Edg/117.0.2045.60', '2023-11-08 11:04:53.523',
        '6E6BFE36FE85:D119RPOBSBJKST-R:XXXXXX', 'CloudBeaver');

INSERT INTO cloudbeaver.cb_auth_attempt_info (auth_id, auth_provider_id, auth_provider_configuration_id, auth_state, create_time)
VALUES ('13ae7c01-5a49-48cf-aa26-1b66cba97b58', 'reverseProxy', NULL, '{"user":"admin@hellodata.ch"}', '2023-11-08 08:53:49.342204'),
       ('31895766-182f-4730-98f3-ea77a30eecd1', 'local', NULL, '{"user":"admin"}', '2023-11-08 08:54:02.50759'),
       ('4f24dc20-7888-42c6-94aa-b9425ca3e44d', 'local', NULL, '{"user":"hellodata"}', '2023-11-08 08:54:07.311548'),
       ('9f3bbe3e-d830-4d41-bec1-19bfee4f5c4f', 'reverseProxy', NULL, '{"user":"admin@hellodata.ch"}', '2023-11-08 10:18:01.665794'),
       ('ca4b02ae-7b7b-4dca-9504-8c7ae327a2d4', 'reverseProxy', NULL, '{"user":"admin@hellodata.ch"}', '2023-11-08 10:18:07.289053'),
       ('5112c06c-ffc2-4df7-bfb4-365dd314dedf', 'reverseProxy', NULL, '{"user":"admin@hellodata.ch"}', '2023-11-08 11:04:50.195136'),
       ('8610a553-c867-4e03-bc55-82c141f72a22', 'reverseProxy', NULL, '{"user":"admin@hellodata.ch"}', '2023-11-08 11:18:02.631224'),
       ('885a6cc5-79e5-4de5-97f4-022a79926273', 'reverseProxy', NULL, '{"user":"nicolas.schmid@bedag.ch"}', '2023-11-08 13:41:44.998895'),
       ('8ca20fab-e186-4b67-80f8-04ae918b9ea4', 'reverseProxy', NULL, '{"user":"nicolas.schmid@bedag.ch"}', '2023-11-08 13:41:46.1009'),
       ('c7e3298b-2567-4ee9-a736-1defe3e0a8dc', 'reverseProxy', NULL, '{"user":"micha.eichmann@bedag.ch"}', '2023-11-09 08:48:32.401889');
INSERT INTO cloudbeaver.cb_auth_attempt_info (auth_id, auth_provider_id, auth_provider_configuration_id, auth_state, create_time)
VALUES ('9673b9fd-66f6-45ec-a128-ef5defe3afde', 'local', NULL, '{"user":"admin"}', '2023-11-09 08:48:37.060295'),
       ('17ac04bd-eb25-4985-8d82-ba36860ec5f6', 'local', NULL, '{"user":"hellodata"}', '2023-11-09 08:48:42.71367'),
       ('136f52a8-3f96-46a0-b0cd-2d8da12c0024', 'reverseProxy', NULL, '{"user":"micha.eichmann@bedag.ch"}', '2023-11-09 08:48:51.380818');



INSERT INTO cloudbeaver.cb_auth_attempt (auth_id, auth_status, auth_error, app_session_id, session_id, session_type, app_session_state, create_time)
VALUES ('13ae7c01-5a49-48cf-aa26-1b66cba97b58', 'IN_PROGRESS', NULL, 'td7ruby88nsr1sf999ayw544j0', NULL, 'CloudBeaver',
        '{"lastRemoteAddr":"10.0.23.23","trustedUserTeams":[""],"lastRemoteUserAgent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36 Edg/117.0.2045.60"}',
        '2023-11-08 08:53:49.342204'),
       ('31895766-182f-4730-98f3-ea77a30eecd1', 'ERROR', 'Invalid user credentials', 'td7ruby88nsr1sf999ayw544j0', NULL, 'CloudBeaver',
        '{"lastRemoteAddr":"10.0.23.23","lastRemoteUserAgent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36 Edg/117.0.2045.60"}',
        '2023-11-08 08:54:02.50759'),
       ('4f24dc20-7888-42c6-94aa-b9425ca3e44d', 'ERROR', 'Invalid user credentials', 'td7ruby88nsr1sf999ayw544j0', NULL, 'CloudBeaver',
        '{"lastRemoteAddr":"10.0.23.23","lastRemoteUserAgent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36 Edg/117.0.2045.60"}',
        '2023-11-08 08:54:07.311548'),
       ('9f3bbe3e-d830-4d41-bec1-19bfee4f5c4f', 'IN_PROGRESS', NULL, '1uo0w4ppdgfkj7c3l5kav7grl1', NULL, 'CloudBeaver',
        '{"lastRemoteAddr":"10.0.23.23","trustedUserTeams":[""],"lastRemoteUserAgent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36 Edg/117.0.2045.60"}',
        '2023-11-08 10:18:01.665794'),
       ('ca4b02ae-7b7b-4dca-9504-8c7ae327a2d4', 'IN_PROGRESS', NULL, '1uo0w4ppdgfkj7c3l5kav7grl1', NULL, 'CloudBeaver',
        '{"lastRemoteAddr":"10.0.23.23","trustedUserTeams":[""],"lastRemoteUserAgent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36 Edg/117.0.2045.60"}',
        '2023-11-08 10:18:07.289053'),
       ('5112c06c-ffc2-4df7-bfb4-365dd314dedf', 'EXPIRED', NULL, '1dg7lgksjjx7p1f8hstc6atude2', 'ada57dc4-6e69-4123-a7b5-a4f0112af3de', 'CloudBeaver',
        '{"lastRemoteAddr":"10.0.23.127","trustedUserTeams":["ADMIN","RG_READ_DM","RG_READ_DWH"],"lastRemoteUserAgent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36 Edg/117.0.2045.60"}',
        '2023-11-08 11:04:50.195136'),
       ('8610a553-c867-4e03-bc55-82c141f72a22', 'EXPIRED', NULL, '1qu0mwtfu2lnct7u7kxqvw25k3', 'e9506d01-2b01-42e1-a0df-6f9c4d9f4597', 'CloudBeaver',
        '{"lastRemoteAddr":"10.0.23.127","trustedUserTeams":["ADMIN","RG_READ_DM","RG_READ_DWH"],"lastRemoteUserAgent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36 Edg/117.0.2045.60"}',
        '2023-11-08 11:18:02.631224'),
       ('885a6cc5-79e5-4de5-97f4-022a79926273', 'IN_PROGRESS', NULL, '1uo0w4ppdgfkj7c3l5kav7grl1', NULL, 'CloudBeaver',
        '{"lastRemoteAddr":"10.0.23.23","trustedUserTeams":["VG_READ_DM","VG_READ_DWH","RG_READ_DM","ADMIN","RG_READ_DWH"],"lastRemoteUserAgent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36 Edg/117.0.2045.60"}',
        '2023-11-08 13:41:44.998895'),
       ('8ca20fab-e186-4b67-80f8-04ae918b9ea4', 'IN_PROGRESS', NULL, '1uo0w4ppdgfkj7c3l5kav7grl1', NULL, 'CloudBeaver',
        '{"lastRemoteAddr":"10.0.23.23","trustedUserTeams":["VG_READ_DM","VG_READ_DWH","RG_READ_DM","ADMIN","RG_READ_DWH"],"lastRemoteUserAgent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36 Edg/117.0.2045.60"}',
        '2023-11-08 13:41:46.1009'),
       ('c7e3298b-2567-4ee9-a736-1defe3e0a8dc', 'IN_PROGRESS', NULL, 'td7ruby88nsr1sf999ayw544j0', NULL, 'CloudBeaver',
        '{"trustedUserTeams":["VG_READ_DM","VG_READ_DWH","RG_READ_DM","ADMIN","RG_READ_DWH"]}', '2023-11-09 08:48:32.401889');
INSERT INTO cloudbeaver.cb_auth_attempt (auth_id, auth_status, auth_error, app_session_id, session_id, session_type, app_session_state, create_time)
VALUES ('9673b9fd-66f6-45ec-a128-ef5defe3afde', 'ERROR', 'Invalid user credentials', 'td7ruby88nsr1sf999ayw544j0', NULL, 'CloudBeaver',
        '{"lastRemoteAddr":"10.0.23.23","lastRemoteUserAgent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36 Edg/117.0.2045.60"}',
        '2023-11-09 08:48:37.060295'),
       ('17ac04bd-eb25-4985-8d82-ba36860ec5f6', 'ERROR', 'Invalid user credentials', 'td7ruby88nsr1sf999ayw544j0', NULL, 'CloudBeaver',
        '{"lastRemoteAddr":"10.0.23.23","lastRemoteUserAgent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36 Edg/117.0.2045.60"}',
        '2023-11-09 08:48:42.71367'),
       ('136f52a8-3f96-46a0-b0cd-2d8da12c0024', 'IN_PROGRESS', NULL, 'td7ruby88nsr1sf999ayw544j0', NULL, 'CloudBeaver',
        '{"lastRemoteAddr":"10.0.23.23","trustedUserTeams":["VG_READ_DM","VG_READ_DWH","RG_READ_DM","ADMIN","RG_READ_DWH"],"lastRemoteUserAgent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36 Edg/117.0.2045.60"}',
        '2023-11-09 08:48:51.380818');


INSERT INTO cloudbeaver.cb_auth_token
(token_id, refresh_token_id, session_id, user_id, auth_role, expiration_time, refresh_token_expiration_time, create_time)
VALUES ('w0RQLZKsqo3O2pbxaYRqh0pkTQHeidbo', 'pNnrgdJIX425f8owJgZZTp5U96Yrzhxw', 'f0a0748b-40e9-4836-9bb9-35871b290f42', 'admin@hellodata.ch', NULL, '2023-10-16 22:58:05.484',
        '2023-10-19 22:38:05.484', '2023-10-16 22:38:05.484');
