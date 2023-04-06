/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_GroupMinFeeDel] 
	@GroupMinFeeId INT, 
	@UserId INT, 
	@LoginIp VARCHAR (50)	= '', 
	@ErrCode INT = 0 OUTPUT, 
	@ErrMsg VARCHAR(4000) = '' OUTPUT
AS
/*  
	 Created: 20200703@Mason [#134492]
	 Task: Delete group min fee
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20200703@Mason: Implement Group Min Fee [#134492]
		- 20230417@Danny: Insert new log with more information [#FeatureID 175125]
	 Params:

	 Explannation: 
*/

BEGIN
	SET NOCOUNT ON
	DECLARE @logSPData NVARCHAR(MAX), @logSPDataOld NVARCHAR(MAX), @actionID INT = 1502, @startRun DATETIME, @endRun DATETIME, @duration INT

	SET @startRun = GETDATE()

	SELECT @logSPDataOld = 
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

		WHERE lg.GroupMinFeeID = @GroupMinFeeId
		FOR JSON PATH, WITHOUT_ARRAY_WRAPPER 
	)

	-- Remove party assignment in group
	DELETE dbo.LA_GroupMinFeeAssignment WITH(ROWLOCK)
	WHERE GroupMinFeeID = @GroupMinFeeId
	IF @@ERROR > 0
	BEGIN
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 516
		RETURN
	END

	-- Remove fee setting
	DELETE dbo.LA_GroupMinFeeDetail WITH(ROWLOCK)
	WHERE GroupMinFeeID = @GroupMinFeeId
	IF @@ERROR > 0
	BEGIN
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 516
		RETURN
	END

	-- Remove group header
	DELETE dbo.LA_GroupMinFeeHeader WITH(ROWLOCK)
	WHERE GroupMinFeeID = @GroupMinFeeId
	IF @@ERROR > 0
	BEGIN
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 516
		RETURN
	END

	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)

	-- Write Log
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIp
		,@SPName		= 'LA_GroupMinFeeDel'
		,@CustId		= @GroupMinFeeID
		,@Duration		= @duration
		,@TrackingValue2 = @LogSPData
		,@TrackingValue = @LogSPDataOld
		,@ActionID		 = @actionID
END
GO