USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_UserUpdIsActive]    Script Date: 9/8/2014 5:03:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.OA_UsersModify    Script Date: 10/21/2011 7:48:20 PM ******/
ALTER PROCEDURE [dbo].[LA_UserUpdIsActive]
	 @UserID		INT
     ,@IsActive	BIT
	,@Creator		INT	
	,@Language	VARCHAR(20) = 'en-us'
	,@LoginIP		VARCHAR(30)=''
	,@ErrCode		INT = 0 OUTPUT  
	,@ErrMsg		NVARCHAR(1000) = '' OUTPUT 
AS
/*  
 * Created: 20140820@Florent
 * Task : Set active / in-active a User
 * DB: DB052.bodb_Licensee  
 *  
 * Revisions:     
*/
SET NOCOUNT ON
BEGIN
    DECLARE @startRun	DATETIME  
	    ,@endRun		DATETIME  
	    ,@duration	INT
	    ,@LogSPData	VARCHAR(5000)
	    ,@LogSPDataOld VARCHAR(5000)
	
    SET @startRun=GETDATE()

    IF EXISTS(SELECT TOP 1 1 FROM dbo.LA_User WITH(NOLOCK) WHERE UserID = @UserID)
    BEGIN
	    DECLARE @UserName	   NVARCHAR(100)
			 ,@DisplayName   NVARCHAR(100)
			 ,@StatusID	   TINYINT
			 ,@ModifiedDate  DATETIME
	    SELECT  @UserName = UserName	 
			 ,@DisplayName = DisplayName
			 ,@StatusID = StatusID
			 ,@ModifiedDate = ModifiedDate
	    FROM  dbo.LA_User WITH(NOLOCK)
	    WHERE UserID = @UserID

	    SELECT @LogSPDataOld ='<LA_UserUpdIsActive CustID="'+ coalesce(cast(@UserID as varchar(10)),space(1)) + '" ' +  	
		    'UserName="'+ coalesce(cast(@UserName as varchar(20)),space(1)) + '" ' +  
		    'DisplayName="'+ coalesce(cast(@DisplayName as varchar(20)),space(1)) + '" ' +  
		    'StatusID="'+ coalesce(cast(@StatusID as varchar(20)),space(1)) + '" ' +  
		    'ModifiedDate="'+ coalesce(cast(@ModifiedDate as varchar(20)),space(1)) + '" ' +  
		    'Language="'+ coalesce(cast(@Language as varchar(20)),space(1)) + '" ' +  
		    'UserID="'+ coalesce(cast(@Creator as varchar(20)),space(1)) + '" ' + 
		    'IP="'+ coalesce(cast(@LoginIP as varchar(30)),space(1)) + '" />'  

	
	    BEGIN
		    UPDATE dbo.LA_User WITH(UPDLOCK,ROWLOCK)
		    SET	 StatusID = @IsActive
			    ,ModifiedDate = GETDATE() 				
		    WHERE
			    UserID = @UserID
	    END

	    IF @@Error>0
	    BEGIN
		    SELECT @ErrCode=100, @ErrMsg='Fail to update information of the UserID '+CONVERT(varchar(10),@UserID)
		    RETURN
	    END
    END

    SELECT @LogSPData ='<LA_UserUpdIsActive CustID="'+ coalesce(cast(@UserID as varchar(10)),space(1)) + '" ' +  	
	    'UserName="'+ coalesce(cast(@UserName as varchar(20)),space(1)) + '" ' +  
	    'DisplayName="'+ coalesce(cast(@DisplayName as varchar(20)),space(1)) + '" ' +  
	    'StatusID="'+ coalesce(cast(@IsActive as varchar(20)),space(1)) + '" ' +  
	    'ModifiedDate="'+ coalesce(cast(@ModifiedDate as varchar(20)),space(1)) + '" ' +  
	    'Language="'+ coalesce(cast(@Language as varchar(20)),space(1)) + '" ' +  
	    'UserID="'+ coalesce(cast(@Creator as varchar(20)),space(1)) + '" ' +  
	    'IP="'+ coalesce(cast(@LoginIP as varchar(30)),space(1)) + '" />'  

    SET @endRun = getdate()  
    SET @duration  = datediff (millisecond,@startRun,@endRun)   

    EXEC dbo.OA_WriteLog_UserLog_RunSP  
	    @UserID = @Creator,   
	    @CustID = @UserID,
	    @SPName='LA_UserUpdIsActive',
	    --@ActionID = 0,  
	    @TrackingValue = @LogSPData,  
	    @TrackingValue2 = @LogSPDataOld,  
	    @duration = @duration
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_UserUpdIsActive] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_UserUpdIsActive] TO bodbAdminNet 
