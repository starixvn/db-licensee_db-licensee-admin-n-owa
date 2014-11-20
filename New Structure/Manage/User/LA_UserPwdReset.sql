USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_UserPwdReset]    Script Date: 9/8/2014 5:01:39 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.OA_UserPwdReset    Script Date: 10/21/2011 7:48:20 PM ******/
ALTER PROCEDURE [dbo].[LA_UserPwdReset]
	@AdminID int,	
	@UserID int,	
	@Pwd varchar(50),
	@UserSalt varchar(50),   
	@Language varchar(20) = 'en-us',
	@LoginIP varchar(30)='',
	@ErrCode int = 0 OUTPUT,  
	@ErrMsg nvarchar(1000) = '' OUTPUT  
AS

/*
	Created by: [20140820@Florent]
	Task: Reset Pwd of a Licensee user
	DB: DB052.bodb_Licensee
	Revisions:
*/

SET NOCOUNT ON
IF EXISTS (SELECT 1 FROM dbo.LA_User (nolock) WHERE  UserID = @UserID)
BEGIN
    DECLARE @startRun datetime  
	    ,@endRun datetime  
	    ,@duration int  
	    ,@LogSPData varchar(5000)  
	    ,@LogSPDataOld varchar(5000)  
	
    set @startRun = getdate()  

    Select @LogSPDataOld ='<LA_UserPwdReset UserID="'+ coalesce(cast(@UserID as varchar(50)),space(1)) + '" ' +  
     'Pwd = "'+ coalesce(cast(UserPwd as varchar(20)),space(1)) + '" ' +
	'UserSalt = "'+ coalesce(cast(UserSalt as varchar(20)),space(1)) + '" ' +
	'Modifier = "'+ coalesce(cast(@AdminID as varchar(20)),space(1)) + '" ' +  
	'Language="'+ coalesce(cast(@Language as varchar(20)),space(1)) + '" ' +  
	'IP="'+ coalesce(cast(@LoginIP as varchar(30)),space(1)) + '" />'
	FROM dbo.LA_User with (ROWLOCK)
	WHERE  UserID = @UserID

    UPDATE dbo.LA_User with (ROWLOCK,UPDLOCK)
    SET 
	    UserPwd = @Pwd,   
	    UserSalt = @UserSalt  
    WHERE 
	    UserID = @UserID
	
    IF @@Error>0
    BEGIN
	    SELECT @ErrCode=1, @ErrMsg='Fail to reset password'
	    RETURN
    END

    Select @LogSPData ='<LA_UserPwdReset CustID="'+ coalesce(cast(@UserID as varchar(50)),space(1)) + '" ' +  
	'Pwd = "'+ coalesce(cast(@Pwd as varchar(20)),space(1)) + '" ' +
	'UserSalt = "'+ coalesce(cast(@UserSalt as varchar(20)),space(1)) + '" ' +
	'Modifier = "'+ coalesce(cast(@AdminID as varchar(20)),space(1)) + '" ' +   
	'Language="'+ coalesce(cast(@Language as varchar(20)),space(1)) + '" ' +  
	'IP="'+ coalesce(cast(@LoginIP as varchar(30)),space(1)) + '" />'  

    set @endRun = getdate()  
    set @duration  = datediff (millisecond,@startRun,@endRun)   
    ---------------------------  
    EXEC dbo.OA_WriteLog_UserLog_RunSP  
	@UserID = @AdminID,   
	@CustID = @UserID,  
	@SPName='LA_UserPwdReset',
	@ActionID = 2,  
	@TrackingValue = @LogSPData,  
	@TrackingValue2 = @LogSPDataOld,  
	@duration = @duration

END
ELSE
BEGIN
	select @ErrMsg = case @Language when 'en-us' then 'This user does not exist!'
         when 'zh-cn' then 'This user does not exist!'
         when 'zh-tw' then 'This user does not exist!'
         when 'Ja' then 'This user does not exist!'
         when 'TH' then 'This user does not exist!'
         when 'KO' then 'This user does not exist!'
         else 'This user does not exist!'
        end ,@ErrCode=102 
    return    
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_UserPwdReset] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_UserPwdReset] TO bodbAdminNet 

