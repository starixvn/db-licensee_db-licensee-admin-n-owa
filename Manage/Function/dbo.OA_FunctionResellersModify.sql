ALTER PROCEDURE [dbo].[OA_FunctionResellersModify]
	@FunctionID int,	
	@ResellerIDs varchar(5500)
	,@AdminID int
	,@Language varchar(20) = 'en-us'
	,@LoginIP varchar(30)=''
	,@ErrCode int = 0 OUTPUT  
	,@ErrMsg nvarchar(1000) = '' OUTPUT
AS
/*  
 * Created: 20111125@Kos
 * Task : Assign reseller(s) to function
 * DB: DB052.bodb_Reseller  
 *  
 * Revisions:     
*/
SET NOCOUNT ON
DECLARE @startRun datetime  
	,@endRun datetime  
	,@duration int
	,@LogSPData varchar(5000)
	
SET @startRun=GETDATE()	

INSERT INTO dbo.OA_FunctionResellers (
	FunctionID,
	ResellerID
)
SELECT
	@FunctionID,
	Val AS ResellerID
FROM dbo.strSplit(@ResellerIDs,',')

IF @@Error>0
BEGIN
	SELECT @ErrCode=1, @ErrMsg='Fail to insert data of ResellerID '+ @ResellerIDs+' and FunctionID '+CONVERT(varchar(10),@FunctionID)
	RETURN
END

SELECT @LogSPData ='<OA_FunctionResellersModify FunctionID="'+ coalesce(cast(@FunctionID as varchar(10)),space(1)) + '" ' +  
	'ResellerID="'+ coalesce(@ResellerIDs ,space(1)) + '" ' +  
	'Language="'+ coalesce(cast(@Language as varchar(20)),space(1)) + '" ' +  
	'UserID="'+ coalesce(cast(@AdminID as varchar(20)),space(1)) + '" ' + 
	'IP="'+ coalesce(cast(@LoginIP as varchar(30)),space(1)) + '" />'  

SET @endRun = getdate()  
SET @duration  = datediff (millisecond,@startRun,@endRun)   

EXEC dbo.OA_WriteLog_UserLog_RunSP  
	@UserID = @AdminID,   
	@CustID = 0,
	@SPName='OA_FunctionResellersModify',
	--@ActionID = 0,  
	@TrackingValue = @LogSPData,  
	@duration = @duration
 
GO
GRANT EXECUTE ON [dbo].[OA_FunctionResellersModify] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_FunctionResellersModify] TO [vnteam] 	 