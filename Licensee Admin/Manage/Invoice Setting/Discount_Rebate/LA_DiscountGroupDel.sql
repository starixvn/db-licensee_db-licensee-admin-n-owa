USE bodb_licensee
GO
ALTER PROCEDURE dbo.LA_DiscountGroupDel @DiscountGroupId INT
	, @UserId INT
	, @LoginIp VARCHAR (50)	= ''

	, @ErrCode INT = 0 OUTPUT
	, @ErrMsg VARCHAR(4000) = '' OUTPUT
	, @GroupIdOut SMALLINT = 0 OUTPUT
AS
/*  
	 Created: 20150422@Patrick
	 Task : Delete discount group
	 DB: DB052.bodb_Licensee
	 Revisions:     
		
	 Params:
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @startRun DATETIME, @endRun DATETIME, @duration INT, @logSPData VARCHAR(MAX)
		, @logSPDataOld	VARCHAR(MAX), @xml XML
	SET @startRun = GETDATE()

	--validate this discount has applied to Invoice yet
	DECLARE @PayerIdList VARCHAR(4000)
	SELECT COALESCE(@PayerIdList + ',' + CAST(a.PartyId AS VARCHAR), CAST(a.PartyId AS VARCHAR))
	FROM dbo.LA_DiscountGroupAssignment a WITH(NOLOCK)
	WHERE DiscountGroupId = @DiscountGroupId

	--get old data for write log
	SET @xml = (
			SELECT DiscountGroupId AS '@gd'
				, DiscountGroupName AS '@gn'
				, CurrencyId AS '@c'
				, FromDate AS '@fd'
				, ToDate AS '@td'
				, DiscountGroupType AS '@dt'
				, Priority AS '@pr'
				, (SELECT DiscountGroupId AS '@dg'
					, FromAmount AS '@fam'
					, ToAmount AS '@tam'
					, Rate AS '@r'
				FROM dbo.LA_DiscountGroupDetail WITH(NOLOCK) WHERE DiscountGroupId = @DiscountGroupId
				FOR XML PATH('x'), TYPE)
				, (SELECT DiscountGroupId AS '@gd'
					, ProductId AS '@p'
				FROM dbo.LA_DiscountGroupProduct WHERE DiscountGroupId = @DiscountGroupId
				FOR XML PATH('y'), TYPE)
				, (SELECT DiscountGroupId AS '@gd'
					, PartyID AS '@pa'
				FROM dbo.LA_DiscountGroupAssignment WHERE DiscountGroupId = @DiscountGroupId
				FOR XML PATH('z'), TYPE)
			FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK) WHERE DiscountGroupId = @DiscountGroupId
			FOR XML PATH('r'), TYPE)

	SET @logSPDataOld = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"')

	IF ISNULL(@PayerIdList, '') <> ''
	BEGIN
		EXEC dbo.LA_Discount_ValidatePayerAssignment @DiscountGroupId = @DiscountGroupId
			, @PayerIdList  = @PayerIdList
			, @Mode = 'R'

			, @ErrCode = @ErrCode OUTPUT
			, @ErrMsg = @ErrMsg OUTPUT
		IF @ErrCode > 0
		BEGIN
			SELECT @ErrMsg = 'Cannot delete the group, it is being applied.', @ErrCode = 515
			RETURN
		END
	END

	--remove assignment
	DELETE dbo.LA_DiscountGroupAssignment WITH(ROWLOCK)
	WHERE DiscountGroupId = @DiscountGroupId
	IF @@ERROR > 0
	BEGIN
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 516
		RETURN
	END

	--remove product
	DELETE dbo.LA_DiscountGroupProduct WITH(ROWLOCK)
	WHERE DiscountGroupId = @DiscountGroupId
	IF @@ERROR > 0
	BEGIN
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 516
		RETURN
	END

	--remove detail
	DELETE dbo.LA_DiscountGroupDetail WITH(ROWLOCK)
	WHERE DiscountGroupId = @DiscountGroupId
	IF @@ERROR > 0
	BEGIN
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 516
		RETURN
	END

	--remove header
	DELETE dbo.LA_DiscountGroupHeader WITH(ROWLOCK)
	WHERE DiscountGroupId = @DiscountGroupId
	IF @@ERROR > 0
	BEGIN
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 516
		RETURN
	END

	--write log
	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)

	--get log action
	DECLARE @ActionID INT = 0
	SELECT @ActionID = ActionId
	FROM bodb_CustomerLog.dbo.LogAction_Lic WITH (NOLOCK)
	WHERE SPName = 'LA_DiscountGroupDel'
	
	BEGIN TRY
		EXEC bodb_CustomerLog.dbo.NAP_SpecialCustSetting_WriteLog @UserId = @UserID
			, @IP = @LoginIP
			, @LicenseeID = 0
			, @CurrencyID = 0
			, @SPName = 'LA_DiscountGroupDel'
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
GRANT VIEW DEFINITION ON dbo.LA_DiscountGroupDel TO vnteam
GRANT EXECUTE ON dbo.LA_DiscountGroupDel TO bodbAdminNet
GO
