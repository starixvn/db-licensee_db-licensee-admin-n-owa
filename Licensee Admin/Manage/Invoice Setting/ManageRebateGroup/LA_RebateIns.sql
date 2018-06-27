/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_RebateIns] 
	@GroupName	VARCHAR(50), 
	@FromDate	DATE, 
	@ToDate		DATE, 
	@ProductIds VARCHAR(512) = '', 
	@PartyIds VARCHAR(4000) = '', 
	@Rate		DECIMAL(9, 8), 
	@UserId		INT, 
	@Remark		NVARCHAR(4000), 
	@LoginIp	VARCHAR (50)	= '', 
	@ErrCode	INT = 0 OUTPUT, 
	@ErrMsg		VARCHAR(4000)= '' OUTPUT, 
	@GroupIdOut INT = 0 OUTPUT
AS
/*  
	 Created: 20180528@Parsons [#94282]
	 Task : Enhance Manage Discount group function to support more discount schemes
	 DB: DB052.bodb_licensee   

	 Revisions:  
		- 20180528@Parsons: Create reabte group [#94282]

	 Params:

	 Explannation: 
*/

BEGIN
	SET NOCOUNT ON
	DECLARE @startRun DATETIME, @endRun DATETIME, @duration INT, @logSPData NVARCHAR(MAX), 
			@logSPDataOld	NVARCHAR(MAX), @xml XML,
			@RebateGroupType INT = 2

	SET @startRun = GETDATE()

	--check empty
	IF ISNULL(@GroupName, '') = ''
	BEGIN
		SELECT @ErrCode = 501, @ErrMsg = 'Please fill out group name.'
		RETURN
	END

	--check exists
	IF EXISTS (SELECT 1 FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK) WHERE DiscountGroupName = @GroupName AND DiscountGroupType = @RebateGroupType)
	BEGIN
		SELECT @ErrCode = 502, @ErrMsg = 'Group name exists. Please try again.'
		RETURN
	END

	DECLARE @Products TABLE (ProductId TINYINT)
	DECLARE @Payers TABLE (PayerId INT)

	--parse product rebate group
	IF @ProductIds = ''
	BEGIN
		SELECT @ErrMsg = 'Please select at least 1 product!', @ErrCode = 503
		RETURN	
	END

	INSERT INTO @Products(ProductId)
	SELECT val FROM bodb02.dbo.Lrf_f_StringSplit(@ProductIds, ',')

	--parse assigned payer to group
	IF @PartyIds <> ''
	BEGIN
		INSERT INTO @Payers(PayerId)
		SELECT val FROM bodb02.dbo.Lrf_f_StringSplit(@PartyIds, ',')
	END
	
	--check required fields
	IF @FromDate IS NULL OR @ToDate IS NULL
		OR (NOT EXISTS (SELECT 1 FROM @Products))
		OR @Rate < 0
	BEGIN
		SELECT @ErrMsg = 'Please fill all required field.', @ErrCode = 503
		RETURN
	END

	-- #Region Insert 

	--insert rebate group header
	INSERT INTO dbo.LA_DiscountGroupHeader(DiscountGroupName, DiscountGroupType, CurrencyId, FromDate, ToDate, [Priority], Remark)
	VALUES(@GroupName, @RebateGroupType, 0, @FromDate, @ToDate, 2, @Remark)

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
	INSERT INTO dbo.LA_DiscountGroupProduct(DiscountGroupId, ProductId)
	SELECT DISTINCT @GroupIdOut, ProductId
	FROM @Products

	IF @@ERROR <> 0
	BEGIN
		DELETE dbo.LA_DiscountGroupHeader WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		DELETE dbo.LA_DiscountGroupDetail WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		SELECT @ErrMsg = 'Insert failed. Please try again.', @ErrCode = 503
		RETURN
	END

	--insert rebate group assignment
	INSERT INTO dbo.LA_DiscountGroupAssignment(DiscountGroupId, PartyID)
	SELECT DISTINCT @GroupIdOut, PayerId
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

	--get log action
	DECLARE @ActionID INT = 0
	SELECT @ActionID = ActionId
	FROM bodb_CustomerLog.dbo.LogAction_Lic WITH (NOLOCK)
	WHERE SPName = 'LA_RebateIns'
	
	BEGIN TRY
		EXEC bodb_CustomerLog.dbo.NAP_SpecialCustSetting_WriteLog @UserId = @UserID
			, @IP = @LoginIP
			, @LicenseeID = 0
			, @CurrencyID = 0
			, @SPName = 'LA_RebateIns'
			, @CustId = 0
			, @ActionId = @ActionID
			, @Duration = @duration
			, @Data = @logSPData
			, @OldData = @logSPDataOld		
	END TRY
	BEGIN CATCH
		EXEC bodb_CustomerLog.dbo.WriteLog_UserLog_RunSP @UserID = @UserID
			, @CustID = 0
			, @ActionID = @ActionID
			, @TrackingValue = @LogSPData
			, @TrackingValue2 = @logSPDataOld
			, @duration = @duration
	END CATCH	
END
GO
