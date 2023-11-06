/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_GroupMinFeeUpd]
	@GroupMinFeeID			SMALLINT,
	@GroupName				NVARCHAR(110),
	@FromDate				DATE,
	@ToDate					DATE,
	@LicenseeSettingData	NVARCHAR(MAX),
	@GroupMinFeeSettingData	NVARCHAR(MAX),
	@ErrCode				INT				= 0		OUTPUT, 
	@ErrMsg					VARCHAR(4000)	= ''	OUTPUT,
	@UserId					INT, 
	@LoginIp				VARCHAR (50)	= '',
	@Environment			VARCHAR(50)     = 'LOCAL'
AS
/*
	Created: 20200703@Happy
	Task : Update GroupMinFee
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20200703@Happy: Implement Group Min Fee [#134492]
		- 20230417@Danny: Insert new log with more information [#FeatureID 175125]
		- 20230613@Danny: validation on currency when adding new payer [#188014]

	Param's Explannation:
		@GroupMinFeeHeaderOldData = '<Root>
										<GroupMinFeeHeader>
											<GroupMinFeeID>1</GroupMinFeeID>
											<Name>Group_1</Name>
											<FromDate>20190108</FromDate>
											<ToDate>20500101</ToDate>
										</GroupMinFeeHeader>
									</Root>'
									
		@LicenseeSettingData = '<Root>
									<LicenseeSetting>
										<PartyID>1</PartyID>
										<IsPrimary>1</IsPrimary>
									</LicenseeSetting>
									<LicenseeSetting>
										<PartyID>2</PartyID>
										<IsPrimary>0</IsPrimary>
									</LicenseeSetting>
								</Root>'
		
		@GroupMinFeeSettingData = '<Root>
										<GroupMinFeeSetting>
											<ProductId>0</ProductId>
											<MinimumFee>5000</MinimumFee>
											<MinimumFeeTerm>EUR 5,000 (Waived for the first 3 months after launched)</MinimumFeeTerm>
											<CurrencyId>6</CurrencyId>
											<FromDate>20190108</FromDate>
											<ToDate>20500101</ToDate>
										</GroupMinFeeSetting>
										<GroupMinFeeSetting>
											<ProductId>0</ProductId>
											<MinimumFee>2</MinimumFee>
											<MinimumFeeTerm />
											<CurrencyId>6</CurrencyId>
											<FromDate>20190108</FromDate>
											<ToDate>20190407</ToDate>
										</GroupMinFeeSetting>
									</Root>'
*/
BEGIN
	SET NOCOUNT ON;
	DECLARE @HeaderOldData XML,
			@AssignmentOldData XML,
			@DetailOldData XML

	DECLARE @logSPData NVARCHAR(MAX), @logSPDataOld NVARCHAR(MAX), @actionID INT = 1501, @startRun DATETIME, @endRun DATETIME, @duration INT

	SET @startRun = GETDATE()

	SELECT @logSPDataOld = 
	(
		SELECT lg.Name AS 'gs.gn' ,  FORMAT (lg.FromDate,'MMM dd, yyyy')  'gs.af', FORMAT (lg.ToDate,'MMM dd, yyyy') 'gs.at', l.l AS 'l', gmfs.gmfs 'gmfs'
		FROM LA_GroupMinFeeHeader lg WITH(NOLOCK) 
		CROSS APPLY (
			SELECT 
			(
				SELECT lga.PartyID AS FakeID, lga.PartyID AS pi, op.PartyName AS ln, CASE WHEN lga.IsPrimary = 1 THEN 'Yes' ELSE 'No' END AS pl
				FROM LA_GroupMinFeeAssignment lga WITH(NOLOCK) 
				INNER JOIN	OAS_Party op WITH(NOLOCK) ON   lga.PartyID = op.PartyID
				WHERE lga.GroupMinFeeID = lg.GroupMinFeeID
				FOR JSON PATH
			) l
		) l
		CROSS APPLY (
			SELECT 
			(
				SELECT CASE WHEN  lgd.ProductId = 0 THEN 'Sportsbook' ELSE p3.ProductName END p, 
						 FORMAT(lgd.MinimumFee,'N','en-us') AS mf,
						 lgd.MinimumFeeTerm AS mft,
						 CASE WHEN e.ExchangeID = 142 THEN 'USDT' ELSE e.Code END AS c,
						 lgd.FromDate AS fd,
						 lgd.ToDate AS td,
						 CONVERT(VARCHAR(10), lgd.CurrencyId) + CONVERT(CHAR(8),lgd.FromDate,112) AS FakeID
				FROM LA_GroupMinFeeDetail lgd WITH(NOLOCK) 
				LEFT JOIN Product3rd p3 WITH(NOLOCK) ON lgd.ProductId = p3.Productid
				INNER JOIN CustDB.dbo.Exchange e WITH(NOLOCK) ON lgd.CurrencyId = e.ExchangeID
				WHERE lgd.GroupMinFeeID = lg.GroupMinFeeID
				FOR JSON PATH
			) gmfs
		) gmfs

		WHERE lg.GroupMinFeeID = @GroupMinFeeID
		FOR JSON PATH, WITHOUT_ARRAY_WRAPPER 
	)


	--#Region update LA_GroupMinFeeHeader
	EXEC dbo.LA_GroupMinFeeHeaderUpd @GroupMinFeeID, @GroupName, @FromDate, @ToDate, @HeaderOldData OUTPUT, @ErrCode OUTPUT, @ErrMsg OUTPUT, @Environment = @Environment
	--#Endregion

		--#Region update LA_GroupMinFeeDetail
	IF ISNULL(@ErrCode, 0) = 0
	BEGIN
		EXEC dbo.LA_GroupMinFeeDetailUpd @GroupMinFeeID, @GroupMinFeeSettingData, @DetailOldData OUTPUT, @ErrCode OUTPUT, @ErrMsg OUTPUT  
	END
	
	--#Region update LA_GroupMinFeeAssignment
	IF ISNULL(@ErrCode, 0) = 0
	BEGIN
		EXEC dbo.LA_GroupMinFeeAssignmentUpd @GroupMinFeeID, @LicenseeSettingData, @AssignmentOldData OUTPUT, @ErrCode OUTPUT, @ErrMsg OUTPUT  
	END
	--#Endregion

	--#Endregion
	
	IF @ErrCode <> 0
	BEGIN
		EXEC dbo.LA_GroupMinFeeUpd_RollBack @GroupMinFeeID, @HeaderOldData, @AssignmentOldData, @DetailOldData, @ErrCode OUTPUT, @ErrMsg OUTPUT
		RETURN
	END

	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)

	SELECT @logSPData = 
	(
		SELECT lg.Name AS 'gs.gn' , FORMAT (lg.FromDate,'MMM dd, yyyy')  'gs.af', FORMAT (lg.ToDate,'MMM dd, yyyy') 'gs.at', l.l AS 'l', gmfs.gmfs 'gmfs'
		FROM LA_GroupMinFeeHeader lg WITH(NOLOCK) 
		CROSS APPLY (
			SELECT 
			(
				SELECT lga.PartyID AS FakeID, lga.PartyID AS pi, op.PartyName AS ln, CASE WHEN lga.IsPrimary = 1 THEN 'Yes' ELSE 'No' END AS pl
				FROM LA_GroupMinFeeAssignment lga WITH(NOLOCK) 
				INNER JOIN	OAS_Party op WITH(NOLOCK) ON   lga.PartyID = op.PartyID
				WHERE lga.GroupMinFeeID = lg.GroupMinFeeID
				FOR JSON PATH
			) l
		) l
		CROSS APPLY (
			SELECT 
			(
				SELECT CASE WHEN  lgd.ProductId = 0 THEN 'Sportsbook' ELSE p3.ProductName END p, 
						 FORMAT(lgd.MinimumFee,'N','en-us') AS mf,
						 lgd.MinimumFeeTerm AS mft,
						 CASE WHEN e.ExchangeID = 142 THEN 'USDT' ELSE e.Code END AS c,
						 lgd.FromDate AS fd,
						 lgd.ToDate AS td,
						 CONVERT(VARCHAR(10), lgd.CurrencyId) + CONVERT(CHAR(8),lgd.FromDate,112) AS FakeID
				FROM LA_GroupMinFeeDetail lgd WITH(NOLOCK) 
				LEFT JOIN Product3rd p3 WITH(NOLOCK) ON lgd.ProductId = p3.Productid
				INNER JOIN CustDB.dbo.Exchange e WITH(NOLOCK) ON lgd.CurrencyId = e.ExchangeID
				WHERE lgd.GroupMinFeeID = lg.GroupMinFeeID
				FOR JSON PATH
			) gmfs
		) gmfs

		WHERE lg.GroupMinFeeID = @GroupMinFeeID
		FOR JSON PATH, WITHOUT_ARRAY_WRAPPER 
	)

	-- Write Log
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIp
		,@SPName		= 'LA_GroupMinFeeUpd'
		,@CustId		= @GroupMinFeeID
		,@Duration		= @duration
		,@TrackingValue2 = @LogSPData
		,@TrackingValue = @LogSPDataOld
		,@ActionID		 = @actionID
END
GO