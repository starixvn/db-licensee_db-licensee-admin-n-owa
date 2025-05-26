/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE [dbo].[SH_SabaPlay_DiscountByGrossWinIns]
	@DiscountGroupName	NVARCHAR(110)
	,@DiscountGroupType	TINYINT = 23
	,@BaseCurrencyId	INT
	,@FromDate			DATE
	,@ToDate			DATE
	,@ProductIds		VARCHAR(512) = ''
	,@OperatorIds		VARCHAR(MAX) = ''
	,@DiscountRate		DECIMAL(9, 8)
	,@UserId			INT
	,@LoginIp			VARCHAR(50) = ''
	,@ErrCode			INT = 0 OUTPUT
	,@ErrMsg			VARCHAR(4000) = '' OUTPUT
	,@GroupIdOut		INT = 0 OUTPUT
AS
/*  
	Created: 20250514@Eddie
	DB: DBCUST.bodb_licensee
	Task: SabaPlay - Manage Discount Group for SabaPlay - Add new group

	Revisions:
		- 20250514@Eddie: Initialize SP [RedmineID: #220534]
	Params:
		@DiscountGroupType :
			23 : Discount Group on Lic WL for SabaPlay

*/

BEGIN
	SET NOCOUNT ON
	
	-- For Log
	DECLARE @StartRun DATETIME
		  , @Duration INT
		  , @LogSPData NVARCHAR(MAX)
		  , @LogSPDataOld NVARCHAR(MAX)
		  , @ActionID INT = 1603 -- DBLOG.bodb_CustomerLog.dbo.LA_LogAction.[ActionID]
		  , @SPName VARCHAR(50) = OBJECT_NAME(@@PROCID)

	DECLARE @Products TABLE (ProductId TINYINT)
	DECLARE @Operators TABLE (PartyId INT)

	SET @StartRun = GETDATE()
	
	INSERT INTO @Products(ProductId)
	SELECT DISTINCT value FROM STRING_SPLIT(@ProductIds, ',')
	
	INSERT INTO @Operators(PartyId)
	SELECT DISTINCT value FROM STRING_SPLIT(@OperatorIds, ',')

	-- Validate input data
	BEGIN

		IF ISNULL(@DiscountGroupName, '') = '' OR @FromDate IS NULL OR @ToDate IS NULL OR ISNULL(@BaseCurrencyId, 0) = 0
		BEGIN
			SELECT @ErrCode = 501, @ErrMsg = 'Please fill in all required field!'
			RETURN
		END

		IF @DiscountRate < 0 OR @DiscountRate > 100
		BEGIN
			SELECT @ErrCode = 512, @ErrMsg = 'Discount Rate cannot be negative or greater than 100.'
			RETURN
		END

		IF EXISTS ( SELECT 1
					FROM dbo.LA_DiscountGroupHeader WITH (NOLOCK)
					WHERE DiscountGroupName = @DiscountGroupName
					  AND DiscountGroupType = 23
		)
		BEGIN
			SELECT @ErrCode = 502, @ErrMsg = 'Group Name already exists. Please try another one!'
			RETURN
		END

		IF @ProductIds = ''
		BEGIN
			SELECT @ErrCode = 503, @ErrMsg = 'Please select at least 1 product!'
			RETURN	
		END

		IF @OperatorIds = ''
		BEGIN
			SELECT @ErrCode = 504, @ErrMsg = 'Please select at least 1 operator!'
			RETURN	
		END

		IF EXISTS (
			SELECT 1
			FROM @Products p
				LEFT JOIN dbo.vw_SabaPlay_Products vw WITH (NOLOCK) ON vw.ProductId = p.ProductId
			WHERE vw.ProductId IS NULL
		)
		BEGIN
			SELECT @ErrCode = 505, @ErrMsg = 'Product(s) do not exist.'
			RETURN
		END

		IF EXISTS (
			SELECT 1
			FROM @Operators p
				LEFT JOIN dbo.OAS_Party op WITH (NOLOCK) ON op.PartyID = p.PartyID
			WHERE op.PartyID IS NULL OR op.PlatformId <> 2
		)
		BEGIN
			SELECT @ErrCode = 506, @ErrMsg = 'Operator(s) do not exist.'
			RETURN
		END

		IF EXISTS (
			SELECT 1
			FROM @Operators p
				LEFT JOIN dbo.OAS_PartyBaseCurrency bc WITH (NOLOCK) ON p.PartyId = bc.PartyId AND bc.FromDate <= @ToDate AND bc.ToDate >= @FromDate
			WHERE bc.PartyId IS NULL OR bc.BaseCurrencyId <> @BaseCurrencyId
		)
		BEGIN
			SELECT @ErrCode = 507, @ErrMsg = 'Operators billing currency must be the same.'
			RETURN
		END

		IF EXISTS (
			SELECT 1
			FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK)
				INNER JOIN dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
				INNER JOIN dbo.LA_DiscountGroupProduct p WITH (NOLOCK) ON p.DiscountGroupId = a.DiscountGroupId
				INNER JOIN @Operators o ON o.PartyId = a.PartyId
				INNER JOIN @Products pt ON pt.ProductId = p.ProductId
			WHERE h.DiscountGroupType = 23 AND h.FromDate <= @ToDate AND h.ToDate >= @FromDate
		)
		BEGIN
			SELECT @ErrCode = 511, @ErrMsg = 'The selected Operator(s) already belong to another discount group with the same product(s). Please adjust your selection!'
			RETURN
		END
	END


	-- #Region Insert 
	BEGIN TRY

		INSERT INTO dbo.LA_DiscountGroupHeader(DiscountGroupName, DiscountGroupType, CurrencyId, FromDate, ToDate, [Priority], ModifiedDate)
		VALUES(@DiscountGroupName, @DiscountGroupType, @BaseCurrencyId, @FromDate, @ToDate, 1, GETDATE())

		SET @GroupIdOut = SCOPE_IDENTITY()

		IF ISNULL(@GroupIdOut, 0) = 0
		BEGIN
			SELECT @ErrCode = 508, @ErrMsg = 'Insert failed. Please try again.'
			RETURN
		END

		INSERT INTO dbo.LA_DiscountGroupDetail(DiscountGroupId, FromAmount, ToAmount, Rate)
		VALUES(@GroupIdOut, 0, 0, @DiscountRate)

		INSERT INTO dbo.LA_DiscountGroupProduct(DiscountGroupId, ProductId, CalculationType)
		SELECT DISTINCT @GroupIdOut, ProductId, 0
		FROM @Products

		INSERT INTO dbo.LA_DiscountGroupAssignment(DiscountGroupId, PartyID, IsApplyDiscount)
		SELECT DISTINCT @GroupIdOut, PartyId, 1
		FROM @Operators
	

		SELECT @LogSPData = (
			SELECT ld.DiscountGroupName AS 'gs.gn'
				  ,CAST (ldg.Rate * 100 AS VARCHAR(50)) + ' %' AS 'gs.dr'
				  ,e.Code  AS 'gs.e'
				  ,FORMAT (ld.FromDate,'MMM dd, yyyy') AS 'gs.af'
				  ,FORMAT (ld.ToDate,'MMM dd, yyyy')   AS 'gs.at'
				  ,pa.val  AS 'gs.pa'
				  ,pig.val AS 'gs.oig'
			FROM dbo.LA_DiscountGroupHeader ld WITH (NOLOCK)
				INNER JOIN dbo.LA_DiscountGroupDetail ldg WITH (NOLOCK) ON ld.DiscountGroupId = ldg.DiscountGroupId
				INNER JOIN Custdb.dbo.Exchange e WITH (NOLOCK) ON ld.CurrencyId = e.ExchangeId
				CROSS APPLY (
						SELECT STRING_AGG(op.PartyName, ', ') AS val
						FROM dbo.LA_DiscountGroupAssignment lda WITH (NOLOCK)
							INNER JOIN dbo.OAS_Party op WITH (NOLOCK) ON lda.PartyID = op.PartyID
						WHERE lda.DiscountGroupId = ld.DiscountGroupId
				) pig
				CROSS APPLY 
				(
					SELECT STRING_AGG(vw.ProductName, ', ') AS val
					FROM dbo.LA_DiscountGroupProduct ldp WITH (NOLOCK)
						LEFT JOIN dbo.vw_SabaPlay_Products vw WITH (NOLOCK) ON vw.ProductId = ldp.ProductId
					WHERE ld.DiscountGroupId = ldp.DiscountGroupId
				) pa
			WHERE ld.DiscountGroupId = @GroupIdOut
			FOR JSON PATH, WITHOUT_ARRAY_WRAPPER 
		)

	END TRY
	BEGIN CATCH

		DELETE dbo.LA_DiscountGroupHeader     WITH (ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		DELETE dbo.LA_DiscountGroupDetail     WITH (ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		DELETE dbo.LA_DiscountGroupProduct    WITH (ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		DELETE dbo.LA_DiscountGroupAssignment WITH (ROWLOCK) WHERE DiscountGroupId = @GroupIdOut

		SELECT @ErrCode = 508, @ErrMsg = 'Insert failed. Please try again.'
		RETURN

	END CATCH

	SET @Duration = DATEDIFF(MILLISECOND, @StartRun, GETDATE())

	-- Write Log
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			 = @UserId
		,@IP			 = @LoginIp
		,@SPName		 = @SPName
		,@CustId		 = @GroupIdOut
		,@Duration		 = @Duration
		,@TrackingValue2 = @LogSPData
		,@TrackingValue  = @LogSPDataOld
		,@ActionID		 = @ActionID
END
GO