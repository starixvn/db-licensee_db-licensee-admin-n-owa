ALTER PROCEDURE [dbo].[OA_FunctionLicenseesModify]
	@FunctionID int,
	@ResellerID int,
	@LicenseeIDs varchar(5500) --'1,2,3,4'
	,@AdminID int
	,@Language varchar(20) = 'en-us'
	,@LoginIP varchar(30)=''
	,@ErrCode int = 0 OUTPUT  
	,@ErrMsg nvarchar(1000) = '' OUTPUT 
AS
/*  
 * Created: 20111125@Kos
 * Task : Assign licensee(s) to Function
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
	
SET @startRun=GETDATE()	

INSERT INTO dbo.OA_FunctionLicensees (
	FunctionID,
	ResellerID,
	LicenseeID )
SELECT
	@FunctionID,
	@ResellerID,
	val AS LicenseeID
FROM dbo.strSplit (@LicenseeIDs,',')

IF @@Error>0
BEGIN
	SELECT @ErrCode=1, @ErrMsg='Fail to insert data of LicenseeID '+CONVERT(varchar(10),@LicenseeIDs)+' and FunctionID '+CONVERT(varchar(10),@FunctionID)
	RETURN
END

SELECT @LogSPData ='<OA_FunctionLicenseesModify FunctionID="'+ coalesce(cast(@FunctionID as varchar(10)),space(1)) + '" ' +  
	'LicenseeID="'+ coalesce(@LicenseeIDs  ,space(1)) + '" ' +  
	'Language="'+ coalesce(cast(@Language as varchar(20)),space(1)) + '" ' +  
	'UserID="'+ coalesce(cast(@AdminID as varchar(20)),space(1)) + '" ' +  
	'IP="'+ coalesce(cast(@LoginIP as varchar(30)),space(1)) + '" />'  

SET @endRun = getdate()  
SET @duration  = datediff (millisecond,@startRun,@endRun)   

EXEC dbo.OA_WriteLog_UserLog_RunSP  
	@UserID = @AdminID,   
	@CustID = 0,
	@SPName='OA_FunctionLicenseesModify',
	--@ActionID = 0,  
	@TrackingValue = @LogSPData,  
	@duration = @duration
END

GO
GRANT EXECUTE ON [dbo].[OA_FunctionLicenseesModify] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_FunctionLicenseesModify] TO [vnteam] 