/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_RebateUpd] 
	@GroupId SMALLINT = 0,
	@GroupName	VARCHAR(50), 
	@FromDate	DATE, 
	@ToDate		DATE, 
	@ProductIds VARCHAR(512) = '', 
	@AssignedPartyIds VARCHAR(4000) = '', 
	@Rate		DECIMAL(9, 8), 
	@UserId		INT, 
	@Remark		NVARCHAR(4000), 
	@LoginIp	VARCHAR (50)	= '', 
	@ErrCode	INT = 0 OUTPUT, 
	@ErrMsg		VARCHAR(4000)= '' OUTPUT
AS
/*  
	 Created: 20180528@Parsons [#94282]
	 Task : Enhance Manage Discount group function to support more discount schemes
	 DB: DB052.bodb_licensee   

	 Revisions:  
		- 20180528@Parsons: Update reabte group [#94282]

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
		SELECT @ErrCode = 501, @ErrMsg = 'Group name required. '
		RETURN
	END

	--check exists
	IF EXISTS (SELECT 1 FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK) WHERE DiscountGroupName = @GroupName AND DiscountGroupType = @RebateGroupType AND DiscountGroupId <> @GroupId)
	BEGIN
		SELECT @ErrCode = 502, @ErrMsg = 'Group name exists. Please try again.'
		RETURN
	END

	DECLARE @Products TABLE (ProductId TINYINT)
	DECLARE @Payers TABLE (PayerId INT)

	--parse product rebate group
	IF @ProductIds = ''
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 503
		RETURN	
	END

	INSERT INTO @Products(ProductId)
	SELECT val FROM bodb02.dbo.Lrf_f_StringSplit(@ProductIds, ',')

	--parse assigned payer to group
	IF @AssignedPartyIds <> ''
	BEGIN
		INSERT INTO @Payers(PayerId)
		SELECT val FROM bodb02.dbo.Lrf_f_StringSplit(@AssignedPartyIds, ',')
	END
	
	--check required fields
	IF @FromDate IS NULL OR @ToDate IS NULL
		OR (NOT EXISTS (SELECT 1 FROM @Products))
		OR @Rate < 0
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 504
		RETURN
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
		THEN INSERT(DiscountGroupId, PartyId)
				VALUES(@GroupId, s.PayerId)
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
		THEN INSERT(DiscountGroupId, ProductId)
				VALUES(@GroupId, s.ProductId)
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

	--get log action
	DECLARE @ActionID INT = 0
	SELECT @ActionID = ActionId
	FROM bodb_CustomerLog.dbo.LogAction_Lic WITH (NOLOCK)
	WHERE SPName = 'LA_RebateUpd'
	
	BEGIN TRY
		EXEC bodb_CustomerLog.dbo.NAP_SpecialCustSetting_WriteLog @UserId = @UserID
			, @IP = @LoginIP
			, @LicenseeID = 0
			, @CurrencyID = 0
			, @SPName = 'LA_RebateUpd'
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
