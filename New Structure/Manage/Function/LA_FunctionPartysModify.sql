USE [bodb_licensee]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[LA_FunctionPartysModify]
	 @FunctionID	INT
	,@PartyIDs	VARCHAR(5500) --'1,2,3,4'
	,@Creator		INT
	,@Language	VARCHAR(20) = 'en-us'
	,@LoginIP		VARCHAR(30)=''
	,@ErrCode		INT = 0 OUTPUT  
	,@ErrMsg		NVARCHAR(1000) = '' OUTPUT 
AS
/*  
 * Created: 20140820@Florent
 * Task : Assign party(s) to Function
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
	
SET @startRun=GETDATE()	

IF EXISTS (SELECT TOP 1 1 FROM dbo.LA_FunctionParty fp WITH (NOLOCK) WHERE fp.FunctionID = @FunctionID)
BEGIN
    DECLARE @PartyListOld varchar(5000)=''
    SELECT @PartyListOld = @PartyListOld + cast(PartyID as varchar(30)) + ',' 
	   FROM dbo.LA_FunctionParty WITH (NOLOCK) 
	   WHERE FunctionID = @FunctionID

    SELECT @LogSPData2 ='<LA_FunctionPartysModify FunctionID="'+ coalesce(cast(@FunctionID as varchar(10)),space(1)) + '" ' +  
	'PartyID="'+ coalesce(@PartyListOld  ,space(1)) + '" ' +  
	'Language="'+ coalesce(cast(@Language as varchar(20)),space(1)) + '" ' +  
	'UserID="'+ coalesce(cast(@Creator as varchar(20)),space(1)) + '" ' +  
	'IP="'+ coalesce(cast(@LoginIP as varchar(30)),space(1)) + '" />'

	DELETE FROM dbo.LA_FunctionParty WITH (ROWLOCK) 
	WHERE FunctionID = @FunctionID

	IF @@Error>0
	BEGIN
	   SELECT @ErrCode=1, @ErrMsg='Fail to	unassign LicenseeID '+@PartyListOld+' from FunctionID '+CONVERT(varchar(10),@FunctionID)
	   RETURN
	END
    
END

INSERT INTO dbo.LA_FunctionParty (
	FunctionID,
	PartyID )
SELECT
	@FunctionID,
	val AS PartyID	
FROM dbo.strSplit (@PartyIDs,',')

IF @@Error>0
BEGIN
	SELECT @ErrCode=1, @ErrMsg='Fail to insert data of Party list : '+CONVERT(varchar(10),@PartyIDs)+' and FunctionID '+CONVERT(varchar(10),@FunctionID)
	RETURN
END

SELECT @LogSPData ='<LA_FunctionPartysModify FunctionID="'+ coalesce(cast(@FunctionID as varchar(10)),space(1)) + '" ' +  
	'PartyID="'+ coalesce(@PartyIDs  ,space(1)) + '" ' +  
	'Language="'+ coalesce(cast(@Language as varchar(20)),space(1)) + '" ' +  
	'UserID="'+ coalesce(cast(@Creator as varchar(20)),space(1)) + '" ' +  
	'IP="'+ coalesce(cast(@LoginIP as varchar(30)),space(1)) + '" />'  

SET @endRun = getdate()  
SET @duration  = datediff (millisecond,@startRun,@endRun)   

EXEC dbo.OA_WriteLog_UserLog_RunSP  
	@UserID = @Creator,   
	@CustID = 0,
	@SPName='LA_FunctionPartysModify',
	--@ActionID = 0,  
	@TrackingValue = @LogSPData,  
	@TrackingValue2 = @LogSPData2,
	@duration = @duration
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_FunctionPartysModify] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_FunctionPartysModify] TO bodbAdminNet 

