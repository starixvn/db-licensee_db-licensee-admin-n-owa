/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_HostingFeesDel]
	@HostingFeesId	INT,
	@UserID			INT,
	@LoginIP		VARCHAR (50)	= '',
	@ErrCode		INT				= 0		OUTPUT,
	@ErrMsg			NVARCHAR(1000)	= ''	OUTPUT
AS
/*  
	 Created: 20160615@Bravo
	 Task : Delete hosting fees settings
	 DB: DBCUST.bodb_Licensee  
   
	 Revisions:
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
		- 20230530@Danny: Insert new log with more information [#FeatureID 175125]

	 Params:
		
	 Example:
		EXEC dbo.[LA_HostingFeesDel] 1
*/
BEGIN	
	SET NOCOUNT ON

	-- For writing log
	DECLARE 
		@startRun	DATETIME = GETDATE(),
		@endRun		DATETIME,
		@duration	INT,
		@logData	NVARCHAR(MAX),
		@logDataOld	NVARCHAR(MAX),
		@ActionID	INT = 2002

	IF EXISTS (SELECT 1 FROM dbo.LA_HostingFeesSetting WITH(NOLOCK) WHERE HostingFeesId = @HostingFeesId)
	BEGIN
		SELECT 	@ErrMsg = 'This setting is being used.', @ErrCode = 2	
		RETURN
	END

	
	SELECT @logDataOld = 
	(
		SELECT	   
				f.HostingFeesName 'gs.crn', 
				CASE WHEN e.ExchangeId = 142 THEN 'USDT' ELSE e.Code END 'gs.e',
				rs.rs 'rs'
		
		FROM dbo.LA_HostingFees f WITH(NOLOCK)
			INNER JOIN CustDB.dbo.exchange e WITH(NOLOCK) ON e.ExchangeId = f.BaseCurrencyId
			CROSS APPLY (
				SELECT 
				(
					SELECT 	d.HostingFeesDetailId FakeID,
							t.HostingFeesTypeName + ' - ' + CASE WHEN e1.ExchangeId = 142 THEN 'USDT' ELSE e1.Code END t, 
							CASE WHEN f.HostingFeesTypeId = 2 THEN FORMAT(d.VCMFrom,'N','en-us') ELSE 'N/A'  END amf,
							CASE WHEN f.HostingFeesTypeId = 2 THEN CASE WHEN d.VCMTo = 1000000000 THEN 'Unlimited' ELSE FORMAT(d.VCMTo,'N','en-us') END ELSE 'N/A' END amt,
							FORMAT(d.Amount,'N','en-us') am
					FROM dbo.LA_HostingFeesDetail d WITH(NOLOCK)
					INNER JOIN dbo.LA_HostingFeesTypes t WITH(NOLOCK) ON f.HostingFeesTypeId = t.HostingFeesTypeId
					INNER JOIN CustDB.dbo.exchange e1 WITH(NOLOCK) ON e1.ExchangeId = d.BaseCurrencyId
					WHERE d.HostingFeesId = f.HostingFeesId FOR JSON PATH
				) rs
			) rs
		WHERE f.HostingFeesId = @HostingFeesId  FOR JSON PATH,  WITHOUT_ARRAY_WRAPPER 
	)

	DELETE FROM dbo.LA_HostingFees WHERE HostingFeesId = @HostingFeesId
	DELETE FROM dbo.LA_HostingFeesDetail WHERE HostingFeesId = @HostingFeesId
	
	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 

	-- Write Log
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIp
		,@SPName		= 'LA_HostingFeesDel'
		,@CustId		= @HostingFeesId
		,@Duration		= @duration
		,@TrackingValue2 = @logData
		,@TrackingValue  = @logDataOld
		,@ActionID		 = @actionID

END
GO