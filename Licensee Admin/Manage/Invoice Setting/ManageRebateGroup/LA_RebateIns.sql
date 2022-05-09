/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_RebateIns] 
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
	@ErrMsg				VARCHAR(4000)= '' OUTPUT,
	@GroupIdOut			INT = 0 OUTPUT
AS
/*  
	 Created: 20180528@Parsons [#94282]
	 Task : Enhance Manage Discount group function to support more discount schemes
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20180528@Parsons: Create rebate group [#94282]
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
		- 20220210@Percy: Add param @RebateGroupType to offer Tier Rebate [RedmineID: #163495]
		- 20220506@Percy: Add new rebate type: Rebate on Licensee WL [RedmineID: #1732342]
		- 20220509@Danny: Use String_split built-in function [RemineID: #171831]
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
	IF EXISTS (SELECT 1 FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK) WHERE DiscountGroupName = @GroupName AND DiscountGroupType IN (2, 12, 22))
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
	SELECT value FROM STRING_SPLIT(@ProductIds, ',')

	--parse assigned payer to group
	IF @PartyIds = ''
	BEGIN
		SELECT @ErrCode = 503, @ErrMsg = 'Please add at least one licensee.'
		RETURN	
	END

	INSERT INTO @Payers(PayerId)
	SELECT value FROM STRING_SPLIT(@PartyIds, ',')
	
	--check required fields
	IF @FromDate IS NULL OR @ToDate IS NULL
		OR @Rate < 0
	BEGIN
		SELECT @ErrMsg = 'Please fill all required field.', @ErrCode = 503
		RETURN
	END

	-- check exists setting
	BEGIN
		SELECT @ErrMsg = ''

		SELECT @ErrMsg = MAX (CASE
								WHEN @RebateGroupType = 12 AND h.DiscountGroupType = 12 THEN 'Licensee is in another Tier Rebate group.'
								WHEN @RebateGroupType = 2 AND h.DiscountGroupType = 22 THEN 'Licensee is in another Rebate on Lic WL group.'
								WHEN @RebateGroupType = 22 AND h.DiscountGroupType = 2 THEN 'Licensee is in another Rebate on Lic Fee group.'
								WHEN @RebateGroupType IN (2, 22) AND h.DiscountGroupType = @RebateGroupType AND pt.ProductId IS NOT NULL THEN 'Duplicated product with current group.'
								ELSE '' END)
		FROM @Payers t
			INNER JOIN dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) ON t.PayerId = a.PartyId
			INNER JOIN dbo.LA_DiscountGroupHeader h WITH (NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
			INNER JOIN dbo.LA_DiscountGroupProduct p WITH (NOLOCK) ON p.DiscountGroupId = a.DiscountGroupId
			LEFT JOIN @Products pt ON pt.ProductId = p.ProductId
		WHERE h.DiscountGroupType IN (2, 12, 22)
			AND h.FromDate <= @ToDate AND h.ToDate >= @FromDate

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

	-- #Region Insert 

	--insert rebate group header
	INSERT INTO dbo.LA_DiscountGroupHeader(DiscountGroupName, DiscountGroupType, CurrencyId, FromDate, ToDate, Remark, [Priority], ModifiedDate)
	VALUES(@GroupName, @RebateGroupType, @BaseCurrencyId, @FromDate, @ToDate, @Remark, 2, GETDATE())

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Insert failed. Please try again.', @ErrCode = 503
		RETURN
	END

	SET @GroupIdOut = SCOPE_IDENTITY()
	IF ISNULL(@GroupIdOut, 0) = 0
	BEGIN
		SELECT @ErrMsg = 'Insert failed. Please try again.', @ErrCode = 503
		RETURN
	END

	--insert rebate group detail
	INSERT INTO dbo.LA_DiscountGroupDetail(DiscountGroupId, FromAmount, ToAmount, Rate)
	Values(@GroupIdOut, 0, 0, @Rate)

	IF @@ERROR <> 0
	BEGIN
		DELETE dbo.LA_DiscountGroupHeader WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		SELECT @ErrMsg = 'Insert failed. Please try again.', @ErrCode = 503
		RETURN
	END

	--insert rebate group product
	INSERT INTO dbo.LA_DiscountGroupProduct(DiscountGroupId, ProductId, CalculationType)
	SELECT DISTINCT @GroupIdOut, ProductId, 0
	FROM @Products

	IF @@ERROR <> 0
	BEGIN
		DELETE dbo.LA_DiscountGroupHeader WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		DELETE dbo.LA_DiscountGroupDetail WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		SELECT @ErrMsg = 'Insert failed. Please try again.', @ErrCode = 503
		RETURN
	END

	--insert rebate group assignment
	INSERT INTO dbo.LA_DiscountGroupAssignment(DiscountGroupId, PartyID, IsApplyDiscount)
	SELECT DISTINCT @GroupIdOut, PayerId, 0
	FROM @Payers

	IF @@ERROR <> 0
	BEGIN
		DELETE dbo.LA_DiscountGroupHeader WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		DELETE dbo.LA_DiscountGroupDetail WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		DELETE dbo.LA_DiscountGroupProduct WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		SELECT @ErrMsg = 'Insert failed. Please try again.', @ErrCode = 503
		RETURN
	END
	-- #Endregion Insert 

	--write log
	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)
	SET @xml = (
			SELECT @GroupIdOut AS '@gd'
				, @GroupName AS '@gn'
				, 0 AS '@c'
				, @FromDate AS '@fd'
				, @ToDate AS '@td'
				, @RebateGroupType AS '@dt'
				, @BaseCurrencyId AS '@bc'
				, 2 AS '@pr'
				, (SELECT @GroupIdOut AS '@gd'
					, @Rate AS '@r'
				FOR XML PATH('x'), TYPE)
				, (SELECT @GroupIdOut AS '@gd'
					, ProductId AS '@p'
				FROM @Products
				FOR XML PATH('y'), TYPE)
				, (SELECT @GroupIdOut AS '@gd'
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
		,@SPName		= 'LA_RebateIns'
		,@CustId		= 0
		,@Duration		= @duration
		,@Data			= @logSPData
		,@OldData		= @logSPDataOld
END
GO
