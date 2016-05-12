/*
	Author : Florent.Nguyen
	Date : 2014-10-16
*/
USE bodb_licensee
GO
    UPDATE LA_User WITH (ROWLOCK) SET Username = 'starix1',UserPwd = 'F590AEF467F17F683FB7B67CB173952D84F57ADF',DisplayName = 'StarixIT',UserSalt='rFPS9/0fD8M2eBJ06Q==' WHERE Username ='User_IT'
GO
    UPDATE LA_User WITH (ROWLOCK) SET Username = 'starix2',UserPwd = '284B8D6578483CC43EBC52FB9C0C8CD677B84E7A',DisplayName = 'StarixAdmin',UserSalt ='LxCMhunGeg4sk/YU7g==' WHERE Username ='User_Admin'
GO
    UPDATE LA_User WITH (ROWLOCK) SET Username = 'starix3',UserPwd = '1F5205C6726A35C50171729FDEFE959E81D7720A',DisplayName = 'StarixNormal',UserSalt='v+gDLhHrhMMQwfcXKQ==' WHERE Username ='User_Normal'
GO
IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_User WHERE Username='twKai')
BEGIN
    INSERT INTO dbo.LA_User (GroupID,Username,UserPwd,DisplayName,UserSalt,StatusID,Creator,CreatedDate,ModifiedDate)
    SELECT 1,Username,UserPwd,Username,UserSalt,1,1,CreatedDate,ModifiedDate
	   FROM dbo.OA_Users
	   WHERE Username ='twKai'
END
