ALTER PROCEDURE [dbo].[OA_FunctionResellersDelete]
	@FunctionID int
	,@AdminID int
	,@Language varchar(20) = 'en-us'
	,@LoginIP varchar(30)=''
	,@ErrCode int = 0 OUTPUT  
	,@ErrMsg nvarchar(1000) = '' OUTPUT
AS
/*  
 * Created: 20111125@Kos
 * Task : Unassign reseller(s) to Function
 * DB: DB052.bodb_Licensee  
 *  
 * Revisions:     
*/
SET NOCOUNT ON
DECLARE @startRun datetime  
	,@endRun datetime  
	,@duration int
	,@LogSPData varchar(5000)
	,@ResellerIDs varchar(5500)
	
SET @startRun=GETDATE()	
SET @ResellerIDs=''
	
	SELECT @ResellerIDs=@ResellerIDs+CONVERT(varchar(10),ResellerID)+','
	FROM dbo.OA_FunctionResellers	WITH(NOLOCK)
	WHERE FunctionID=@FunctionID
	
DELETE FROM dbo.OA_FunctionResellers WITH(ROWLOCK)
WHERE
	FunctionID = @FunctionID
	
IF @@Error>0
BEGIN
	SELECT @ErrCode=1, @ErrMsg='Fail to unassign ResellerID '+@ResellerIDs+' from FunctionID '+CONVERT(varchar(10),@FunctionID)
	RETURN
END

SELECT @LogSPData ='<OA_FunctionResellersDelete FunctionID="'+ coalesce(cast(@FunctionID as varchar(10)),space(1)) + '" ' +  
	'ResellerID="'+ coalesce(@ResellerIDs,space(1)) + '" ' +  
	'Language="'+ coalesce(cast(@Language as varchar(20)),space(1)) + '" ' +  
	'UserID="'+ coalesce(cast(@AdminID as varchar(20)),space(1)) + '" ' +  
	'IP="'+ coalesce(cast(@LoginIP as varchar(30)),space(1)) + '" />'  

SET @endRun = getdate()  
SET @duration  = datediff (millisecond,@startRun,@endRun)   

EXEC dbo.OA_WriteLog_UserLog_RunSP  
	@UserID = @AdminID,   
	@CustID = 0,
	@SPName='OA_FunctionResellersDelete',
	--@ActionID = 0,  
	@TrackingValue = @LogSPData,  
	@duration = @duration
	
GO
GRANT EXECUTE ON [dbo].[OA_FunctionResellersDelete] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_FunctionResellersDelete] TO [vnteam] 	 