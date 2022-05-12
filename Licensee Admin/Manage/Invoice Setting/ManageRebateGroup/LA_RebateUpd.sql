/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_RebateUpd] 
	@GroupId			SMALLINT = 0,
	@GroupName			NVARCHAR(50),
	@FromDate			DATE,
	@ToDate				DATE,
	@ProductIds			VARCHAR(512) = '',
	@PartyIds			VARCHAR(4000) = '',
	@Rate				DECIMAL(9, 8),
	@RebateGroupType	TINYINT,
	@UserId				INT,
	@Remark				NVARCHAR(4000) = '',
	@LoginIp			VARCHAR (50)	= '',
	@ErrCode			INT = 0 OUTPUT,
	@ErrMsg				VARCHAR(4000)= '' OUTPUT
AS
/*  
	 Created: 20180528@Parsons [#94282]
	 Task : Enhance Manage Discount group function to support more discount schemes
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20180528@Parsons: Update rebate group [#94282]
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
		- 20220210@Percy: Add param @RebateGroupType to offer Tier Rebate [RedmineID: #163495]
		- 20220506@Percy: Add new rebate type: Rebate on Licensee WL [RedmineID: #1732342]
*/

BEGIN
	SET NOCOUNT ON
	DECLARE @startRun DATETIME, @endRun DATETIME, @duration INT, @logSPData NVARCHAR(MAX), 
			@logSPDataOld	NVARCHAR(MAX), @xml XML

	SET @startRun = GETDATE()

	--check empty
	IF ISNULL(@GroupName, '') = ''
	BEGIN
		SELECT @ErrCode = 501, @ErrMsg = 'Please fill out group name.'
		RETURN
	END

	--check exists
	IF EXISTS (SELECT 1 FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK) WHERE DiscountGroupName = @GroupName AND DiscountGroupType IN (2, 12, 22) AND DiscountGroupId <> @GroupId)
	BEGIN
		SELECT @ErrCode = 502, @ErrMsg = 'Group name exists. Please try again.'
		RETURN
	END

	DECLARE @Products TABLE (ProductId TINYINT)
	DECLARE @Payers TABLE (PayerId INT)

	--parse product rebate group
	IF @ProductIds = ''
	BEGIN
		SELECT @ErrCode = 503, @ErrMsg = 'Please select at least 1 product!'
		RETURN	
	END

	INSERT INTO @Products(ProductId)
	SELECT val FROM dbo.Lrf_f_StringSplit(@ProductIds, ',')

	--parse assigned payer to group
	IF @PartyIds = ''
	BEGIN
		SELECT @ErrCode = 503, @ErrMsg = 'Please add at least one licensee.'
		RETURN	
	END
		
	INSERT INTO @Payers(PayerId)
	SELECT val FROM dbo.Lrf_f_StringSplit(@PartyIds, ',')
	
	--check required fields
	IF @FromDate IS NULL OR @ToDate IS NULL
		OR (NOT EXISTS (SELECT 1 FROM @Products))
		OR @Rate < 0
	BEGIN
		SELECT @ErrMsg = 'Please fill all required field.', @ErrCode = 503
		RETURN
	END

	-- if group is Rebate on Lic WL or Lic Fee, check exists setting
	IF @RebateGroupType IN (2, 22)
	BEGIN
		SELECT @ErrMsg = ''

		SELECT TOP 1 @ErrMsg = CASE
								WHEN h.DiscountGroupType <> @RebateGroupType THEN 'Licensee is in another Rebate on Lic ' + CASE WHEN h.DiscountGroupType = 2 THEN 'Fee' ELSE 'WL' END + ' group.'
								WHEN pt.ProductId IS NOT NULL THEN 'Duplicated product with current group.'
								END
		FROM @Payers t
			INNER JOIN dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) ON t.PayerId = a.PartyId
			INNER JOIN dbo.LA_DiscountGroupHeader h WITH (NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
			INNER JOIN dbo.LA_DiscountGroupProduct p WITH (NOLOCK) ON p.DiscountGroupId = a.DiscountGroupId
			LEFT JOIN @Products pt ON pt.ProductId = p.ProductId
		WHERE h.DiscountGroupType IN (2, 22)
			AND h.FromDate <= @ToDate AND h.ToDate >= @FromDate
			AND h.DiscountGroupId <> @GroupId

		IF @ErrMsg <> ''
		BEGIN
			SELECT @ErrCode = 503
			RETURN
		END
	END

	-- if group is tier rebate, check base currency all payers
	DECLARE @BaseCurrency TABLE (BaseCurrencyId INT)
	DECLARE @BaseCurrencyId INT = 0

	IF @RebateGroupType = 12
	BEGIN
		INSERT INTO @BaseCurrency (BaseCurrencyId)
		SELECT DISTINCT BaseCurrencyId
		FROM @Payers p
			INNER JOIN dbo.OAS_PartyBaseCurrency bc WITH (NOLOCK) ON p.PayerId = bc.PartyId
		WHERE bc.FromDate <= @ToDate AND bc.ToDate >= @FromDate

		IF @@ROWCOUNT <> 1
		BEGIN
			SELECT @ErrCode = 503, @ErrMsg = 'Licensees billing currency must be the same.'
			RETURN
		END

		SELECT @BaseCurrencyId = BaseCurrencyId FROM @BaseCurrency
	END

	-- #Region Update 
	IF ISNULL(@GroupId, 0) = 0
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 504
		RETURN
	END

	--get old data for write log
	SET @xml = (
			SELECT DiscountGroupId AS '@gd'
				, DiscountGroupName AS '@gn'
				, CurrencyId AS '@c'
				, FromDate AS '@fd'
				, ToDate AS '@td'
				, DiscountGroupType AS '@dt'
				, CurrencyId AS '@bc'
				, [Priority] AS '@pr'
				, Remark AS '@rm'
				, (SELECT DiscountGroupId AS '@dg'
					, FromAmount AS '@fam'
					, ToAmount AS '@tam'
					, Rate AS '@r'
				FROM dbo.LA_DiscountGroupDetail WITH(NOLOCK)
				WHERE DiscountGroupId = @GroupId
				FOR XML PATH('x'), TYPE)
				, (SELECT DiscountGroupId AS '@gd'
					, ProductId AS '@p'
				FROM dbo.LA_DiscountGroupProduct WITH (NOLOCK)
				WHERE DiscountGroupId = @GroupId
				FOR XML PATH('y'), TYPE)
				, (SELECT DiscountGroupId AS '@gd'
					, PartyID AS '@pa'
				FROM dbo.LA_DiscountGroupAssignment WITH (NOLOCK)
				WHERE DiscountGroupId = @GroupId
				FOR XML PATH('z'), TYPE)
			FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK) WHERE DiscountGroupId = @GroupId
			FOR XML PATH('r'), TYPE)

	SET @logSPDataOld = CONVERT(NVARCHAR(MAX), @xml)

	--update rebate group assingment
	;MERGE dbo.LA_DiscountGroupAssignment WITH(ROWLOCK, UPDLOCK) AS t
	USING @Payers AS s
	ON (t.DiscountGroupId = @GroupId AND t.PartyId = s.PayerId)
	WHEN NOT MATCHED BY TARGET
		THEN INSERT(DiscountGroupId, PartyId, IsApplyDiscount)
				VALUES(@GroupId, s.PayerId, 0)
	WHEN NOT MATCHED BY SOURCE AND t.DiscountGroupId = @GroupId
		THEN DELETE;

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 504
		RETURN
	END

	--update rebate group product
	;MERGE dbo.LA_DiscountGroupProduct WITH(ROWLOCK, UPDLOCK) AS t
	USING @Products AS s
	ON (t.DiscountGroupId = @GroupId AND t.ProductId = s.ProductId)
	WHEN NOT MATCHED BY TARGET
		THEN INSERT(DiscountGroupId, ProductId, CalculationType)
				VALUES(@GroupId, s.ProductId, 0)
	WHEN NOT MATCHED BY SOURCE AND t.DiscountGroupId = @GroupId
		THEN DELETE;

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 504
		RETURN
	END

	--update rebate group detail
	UPDATE dbo.LA_DiscountGroupDetail WITH(ROWLOCK, UPDLOCK)
	SET Rate = @Rate
	WHERE DiscountGroupId = @GroupId

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 504
		RETURN
	END

	--update rebate group header
	UPDATE dbo.LA_DiscountGroupHeader WITH(ROWLOCK, UPDLOCK)
	SET DiscountGroupName = @GroupName
		, FromDate = @FromDate
		, ToDate = @ToDate
		, Remark = @Remark
		, ModifiedDate = GETDATE()
		, DiscountGroupType = @RebateGroupType
		, CurrencyId = @BaseCurrencyId
	WHERE DiscountGroupId = @GroupId

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 504
		RETURN
	END

	-- #Endregion Update 

	--write log
	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)
	SET @xml = (
			SELECT @GroupId AS '@gd'
				, @GroupName AS '@gn'
				, 0 AS '@c'
				, @FromDate AS '@fd'
				, @ToDate AS '@td'
				, @RebateGroupType AS '@dt'
				, @BaseCurrencyId AS '@bc'
				, 2 AS '@pr'
				, (SELECT @GroupId AS '@gd'
					, @Rate AS '@r'
				FOR XML PATH('x'), TYPE)
				, (SELECT @GroupId AS '@gd'
					, ProductId AS '@p'
				FROM @Products
				FOR XML PATH('y'), TYPE)
				, (SELECT @GroupId AS '@gd'
					, PayerId AS '@pa'
				FROM @Payers
				FOR XML PATH('z'), TYPE)
			FOR XML PATH('r'), TYPE)

		SET @logSpData = CONVERT(NVARCHAR(MAX), @xml)

	-- Write Log
	EXEC CustDB.dbo.NAP_SpecialCustSetting_WriteLog_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIP
		,@LicenseeID	= 0
		,@CurrencyID	= 0
		,@SPName		= 'LA_RebateUpd'
		,@CustId		= 0
		,@Duration		= @duration
		,@Data			= @logSPData
		,@OldData		= @logSPDataOld
END
GO
