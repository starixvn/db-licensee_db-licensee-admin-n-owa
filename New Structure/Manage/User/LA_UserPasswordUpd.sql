USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_UserPasswordUpd]    Script Date: 9/8/2014 5:01:19 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.OA_UserPasswordUpd    Script Date: 10/21/2011 7:48:20 PM ******/
ALTER PROCEDURE [dbo].[LA_UserPasswordUpd]  
    @AdminID int,
    @UserID int, 
    @OldPwd varchar(50),   
    @NewPwd varchar(50),   
    @UserSalt varchar(50),   
    @Language varchar(20) = 'en-US',  
    @LoginIP varchar(20),  
    @ErrCode int = 0 OUTPUT,  
    @ErrMsg nvarchar(4000) = '' OUTPUT     
AS  
/*  
 * Created: 20140822@Florent
 * Task : User change password
 * DB: DB052.bodb_Licensee  
 *  
 * Revisions:     
*/  
BEGIN  
	SET NOCOUNT ON;  
	
	DECLARE @startRun datetime  
		,@endRun datetime  
		,@duration int
		,@LogSPData varchar(5000)
		,@LogSPDataOld varchar(5000)
		
	SET @startRun=GETDATE()
	
	 Select @LogSPDataOld ='<LA_UserPasswordUpd UserID="'+ coalesce(cast(@UserID as varchar(50)),space(1)) + '" ' +  
     'Pwd = "'+ coalesce(cast(@OldPwd as varchar(20)),space(1)) + '" ' +
	'Modifier = "'+ coalesce(cast(@AdminID as varchar(20)),space(1)) + '" ' +  
	'Language="'+ coalesce(cast(@Language as varchar(20)),space(1)) + '" ' +  
	'IP="'+ coalesce(cast(@LoginIP as varchar(30)),space(1)) + '" />'	

	If EXISTS(SELECT 1 FROM dbo.LA_User WITH(NOLOCK) WHERE UserID=@UserID AND UserPwd<>@OldPwd)
	BEGIN
		SELECT @ErrMsg = CASE @Language WHEN 'en-us' THEN 'Wrong password.'  
			 WHEN 'zh-cn' THEN N'Wrong password.'  
			 WHEN 'zh-tw' THEN N'Wrong password.'  
			 WHEN 'ja' THEN N'Wrong password.'  
			 WHEN 'TH' THEN N'Wrong password.'  
			 WHEN 'KO' THEN N'Wrong password.'  
			 ELSE N'Wrong password.'  
			END ,@ErrCode=101    
		RETURN 
	END

	if EXISTS (SELECT 1 FROM dbo.LA_User WITH (NOLOCK) WHERE @UserId = UserId and StatusID=0)
	Begin
		SELECT @ErrMsg = CASE @Language WHEN 'en-us' THEN 'This user is not active.'  
			 WHEN 'zh-cn' THEN N'This user is not active.'  
			 WHEN 'zh-tw' THEN N'This user is not active.'  
			 WHEN 'ja' THEN N'This user is not active.'  
			 WHEN 'TH' THEN N'This user is not active.'  
			 WHEN 'KO' THEN N'This user is not active.'  
			 ELSE N'This user is not active.'  
			END ,@ErrCode=102
		RETURN 
	END
			
	UPDATE dbo.LA_User with (UPDLOCK,ROWLOCK)
	SET	  UserPwd = @NewPwd,   
		  UserSalt = @UserSalt  
	WHERE UserID = @UserID
	  
	IF (@@ERROR > 0)  
	BEGIN
		SELECT @ErrCode = 100, @ErrMsg = 'Cannot change password'  
		RETURN
	END

	SELECT @LogSPData ='<LA_UserPasswordUpd CustID="'+ coalesce(cast(@UserID as varchar(10)),space(1)) + '" ' +  
		'Pwd = "'+ coalesce(cast(@NewPwd as varchar(20)),space(1)) + '" ' +
		'Modifier = "'+ coalesce(cast(@AdminID as varchar(20)),space(1)) + '" ' +  
		'Language="'+ coalesce(cast(@Language as varchar(20)),space(1)) + '" ' +  
		'IP="'+ coalesce(cast(@LoginIP as varchar(30)),space(1)) + '" />'  

	SET @endRun = getdate()  
	SET @duration  = datediff (millisecond,@startRun,@endRun)   

		EXEC dbo.OA_WriteLog_UserLog_RunSP  
		@UserID = @AdminID,   
		@CustID = @UserID,
		@SPName='LA_UserPasswordUpd',
		--@ActionID = 0,  
		@TrackingValue = @LogSPData,  
		@TrackingValue2 = @LogSPDataOld,  
		@duration = @duration
		
	SET NOCOUNT OFF

END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_UserPasswordUpd] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_UserPasswordUpd] TO bodbAdminNet 

