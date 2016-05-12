USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_UserPartyModify]
	 @UserID	INT
	,@PartyIDs	VARCHAR(5500) --'1,2,3,4'
	,@Creator		INT
	,@Language	VARCHAR(20) = 'en-us'
	,@LoginIP		VARCHAR(30)=''
	,@ErrCode		INT = 0 OUTPUT  
	,@ErrMsg		NVARCHAR(1000) = '' OUTPUT 
AS
/*  
 * Created: 20140820@Florent
 * Task : Assign party(s) to User
 * DB: DB052.bodb_Licensee  
 *  
 * Revisions:     
*/
BEGIN
SET NOCOUNT ON
DECLARE @startRun datetime  
	,@endRun datetime  
	,@duration int
	,@LogSPData varchar(5000)
	,@LogSPData2 varchar(5000)
	,@strPermissionParty Varchar(5500) =''
SET @startRun=GETDATE()	
IF EXISTS (SELECT TOP 1 1 FROM dbo.LA_UserParty up WITH (NOLOCK) WHERE up.UserID = @UserID)
BEGIN
    DECLARE @PartyListOld varchar(5000)=''
    SELECT @PartyListOld = @PartyListOld + cast(PartyID as varchar(30)) + ',' 
	   FROM dbo.LA_UserParty WITH (NOLOCK) 
	   WHERE UserID = @UserID
	   
    SELECT @strPermissionParty = @strPermissionParty + CAST(PartyID AS VARCHAR(10)) +','
	   FROM dbo.LA_UserParty WITH (NOLOCK) 
	   WHERE UserID = @UserID 
	   AND PartyID NOT IN (SELECT PartyID 
						  FROM dbo.LA_UserParty WITH (NOLOCK) 
						  WHERE UserID = @Creator)
    SELECT @strPermissionParty = SUBSTRING(@strPermissionParty,0,LEN(@strPermissionParty))

    SELECT @LogSPData2 ='<LA_UserPartysModify UserID = "'+ coalesce(cast(@UserID as varchar(10)),space(1)) + '" ' +  
	'PartyID = "'+ coalesce(@PartyListOld  ,space(1)) + '" ' +  
	'ModifiedDate = "'+ coalesce(cast(ModifyDate as varchar(20)),space(1)) + '" ' +
	'Modifier = "'+ coalesce(cast(modifier as varchar(20)),space(1)) + '" ' +
	'Language = "'+ coalesce(cast(@Language as varchar(20)),space(1)) + '" ' +  
	'CustID = "'+ coalesce(cast(@Creator as varchar(20)),space(1)) + '" ' +  
	'IP = "'+ coalesce(cast(@LoginIP as varchar(30)),space(1)) + '" />'
	 FROM dbo.LA_UserParty WITH (NOLOCK) 
	   WHERE UserID = @UserID

	DELETE FROM dbo.LA_UserParty WITH (ROWLOCK) 
	WHERE UserID = @UserID

	IF @@Error>0
	BEGIN
	   SELECT @ErrCode=1, @ErrMsg='Fail to	unassign LicenseeID '+@PartyListOld+' from UserID '+CONVERT(varchar(10),@UserID)
	   RETURN
	END
    
END

IF @strPermissionParty != '' 
    BEGIN
	  IF @PartyIDs != ''
	   SELECT @PartyIDs = @PartyIDs + ',' + @strPermissionParty
       ELSE
	   SELECT @PartyIDs = @strPermissionParty
    END

INSERT INTO dbo.LA_UserParty (
	UserID,
	ModifyDate,
	Modifier,
	PartyID,
	StatusID )
SELECT
	@UserID,
	getdate(),
	@creator,
	val AS PartyID,
	1 --default statusID = 1
FROM dbo.strSplit (@PartyIDs,',')

IF @@Error>0
BEGIN
	SELECT @ErrCode=1, @ErrMsg='Fail to insert data of Party list : '+CONVERT(varchar(10),@PartyIDs)+' and UserID '+CONVERT(varchar(10),@UserID)
	RETURN
END

SELECT @LogSPData ='<LA_UserPartysModify UserID = "'+ coalesce(cast(@UserID as varchar(10)),space(1)) + '" ' +  
	'PartyID = "'+ coalesce(@PartyIDs  ,space(1)) + '" ' +  
	'ModifiedDate = "'+ coalesce(cast(getdate() as varchar(20)),space(1)) + '" ' +
	'Modifier = "'+ coalesce(cast(@Creator as varchar(20)),space(1)) + '" ' +
	'Language = "'+ coalesce(cast(@Language as varchar(20)),space(1)) + '" ' +  
	'CustID = "'+ coalesce(cast(@Creator as varchar(20)),space(1)) + '" ' +  
	'IP="'+ coalesce(cast(@LoginIP as varchar(30)),space(1)) + '" />'  

SET @endRun = getdate()  
SET @duration  = datediff (millisecond,@startRun,@endRun)   

EXEC dbo.OA_WriteLog_UserLog_RunSP  
	@UserID = @Creator,   
	@CustID = @UserID,
	@SPName='LA_UserPartysModify',
	--@ActionID = 0,  
	@TrackingValue = @LogSPData,  
	@TrackingValue2 = @LogSPData2,
	@duration = @duration
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_UserPartyModify] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_UserPartyModify] TO bodbAdminNet 
