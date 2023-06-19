/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_HostingFeesPayerSettingsDel]
	@PayerId	INT,
	@UserID		INT,
	@LoginIP	VARCHAR (50)	= '',
	@ErrCode	INT				= 0		OUTPUT,
	@ErrMsg		NVARCHAR(1000)	= ''	OUTPUT
AS
/*
	Created: 201600713@Bruce
	Task : Delete all hosting fees settings of payer
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20160708@Bruce: create
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
		- 20230524@Danny: Insert new log with more information [#FeatureID 175125]
	
	Params:

	Example:
		EXEC dbo.LA_HostingFeesPayerSettingsDel 14
*/
BEGIN	
	SET NOCOUNT ON

	-- For writing log
	DECLARE 
		@startRun	DATETIME = GETDATE(),
		@endRun		DATETIME,
		@duration	INT,
		@logData	NVARCHAR(MAX),
		@logDataOld	NVARCHAR(MAX)

	SELECT @logDataOld = 
		(

			SELECT op.PartyName 'gs.pn' , crs.crs 'crs', ws.ws 'ws'
			FROM   OAS_party op WITH(NOLOCK)
			OUTER APPLY (
				SELECT 
				(
					SELECT
						s.ChargeId FakeID,
						s.ProductName p,
						FORMAT(s.FirstBilling,'MMM dd, yyyy') fb,
						s.BasisOfBilling bb, 
						f.HostingFeesName cr,
						t.HostingFeesTypeName ct,
						FORMAT(s.FromDate,'MMM dd, yyyy') fd,
						FORMAT(s.ToDate,'MMM dd, yyyy') td
					FROM dbo.LA_HostingFeesSetting s WITH (NOLOCK)
						LEFT JOIN dbo.LA_f_Products3rd('') pr ON s.BasedMinimunFees = pr.ProductID
						LEFT JOIN dbo.LA_HostingFees f WITH (NOLOCK) ON s.HostingFeesId = f.HostingFeesId
						LEFT JOIN dbo.LA_HostingFeesTypes t WITH (NOLOCK) ON f.HostingFeesTypeId = t.HostingFeesTypeId
					WHERE s.FromParty = op.PartyID AND s.SettingType = 1  FOR JSON PATH
				) crs
			) crs

			OUTER APPLY (
				SELECT 
				(
					SELECT
						s.ChargeId FakeID,
						s.ProductName wp,
						FORMAT(s.FromDate,'MMM dd, yyyy') wfd,
						FORMAT(s.ToDate,'MMM dd, yyyy') wtd,
						pr.ProductName AS bm
					FROM dbo.LA_HostingFeesSetting s WITH (NOLOCK)
						LEFT JOIN dbo.LA_f_Products3rd('') pr ON s.BasedMinimunFees = pr.ProductID
						LEFT JOIN dbo.LA_HostingFees f WITH (NOLOCK) ON s.HostingFeesId = f.HostingFeesId
						LEFT JOIN dbo.LA_HostingFeesTypes t WITH (NOLOCK) ON f.HostingFeesTypeId = t.HostingFeesTypeId
					WHERE s.FromParty = op.PartyID AND s.SettingType = 2  FOR JSON PATH
				) ws
			) ws
			WHERE  op.PartyID = @PayerId  FOR JSON PATH,  WITHOUT_ARRAY_WRAPPER 
		)

	DELETE FROM dbo.LA_HostingFeesSetting WHERE FromParty = @PayerId

	-- Write Log
	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)

	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIP
		,@SPName		= 'LA_HostingFeesPayerSettingsDel'
		,@CustId		= @PayerId
		,@Duration		= @duration
		,@TrackingValue2 = @LogData
		,@TrackingValue = @LogDataOld
		,@ActionID		 = 1802
END
GO