/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_DiscountAssignmentSettingDel] 	
	@DiscountId				INT	
	, @PayerId				INT
	, @UserID				INT
	, @LoginIP				VARCHAR (50)	= ''
	, @ErrCode				INT				= 0		OUTPUT
	, @ErrMsg				NVARCHAR(1000)	= ''	OUTPUT	
AS
/*  
	 Created: 20150427@Florent
	 Task: Delete discount setting
	 DB: DBCUST.bodb_Licensee  
   
	 Revisions:
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]

	 Params:				
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @startRun DATETIME, @endRun	DATETIME, @duration INT, @logSPData VARCHAR(5000), @logSPDataOld VARCHAR(5000),	@xml XML
	DECLARE @ProductListAll		VARCHAR(100) = ''
			, @MinDate			DATE 
			, @MaxDate			DATE
	DECLARE @Discount AS TABLE(Idx INT IDENTITY(1,1), DiscountGroupId INT, PartyId INT)
	SET @startRun = GETDATE()
	
	IF ISNULL(@DiscountId, 0 ) = 0 OR ISNULL(@PayerId, 0) = 0
		RETURN
	
	INSERT INTO @Discount (DiscountGroupId, PartyId)
	SELECT a.DiscountGroupId, a.PartyID
	FROM dbo.LA_DiscountGroupAssignment a WITH (NOLOCK)		
	WHERE PartyID = @PayerId	
		AND a.DiscountGroupId = @DiscountId

	--check validate existing 
	EXEC dbo.LA_Discount_ValidatePayerAssignment 
		 @DiscountGroupId = @DiscountId		
		, @PayerIdList = @PayerId		
		, @Mode = 'R'
		, @ErrCode = @ErrCode OUTPUT
		, @ErrMsg = @ErrMsg OUTPUT
	IF @ErrCode <> 0 
	BEGIN
		RETURN
	END

	IF EXISTS (SELECT 1 FROM @Discount)
	BEGIN
		SET @xml = (
				SELECT	cs.DiscountGroupId	AS '@dg'
					, cs.PartyId			AS '@p'
				FROM @Discount cs
					INNER JOIN dbo.LA_DiscountGroupAssignment ci WITH (NOLOCK) ON cs.DiscountGroupId = ci.DiscountGroupId AND ci.PartyID = cs.PartyId
				FOR XML PATH('z'), ROOT('r')			
				)
		SET @logSPDataOld = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"')	

		DELETE dbo.LA_DiscountGroupAssignment WITH (ROWLOCK, UPDLOCK)
		WHERE EXISTS (SELECT 1 FROM @Discount d WHERE d.DiscountGroupId = LA_DiscountGroupAssignment.DiscountGroupId AND d.PartyId = LA_DiscountGroupAssignment.PartyID)

		IF @@ERROR <> 0
		BEGIN
			SELECT 	@ErrMsg = 'Delete failed. Please try again.', @ErrCode = 530	
			RETURN
		END
		SET @endRun = GETDATE()
		SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 
	END
	ELSE
	BEGIN
		IF @@ERROR <> 0
		BEGIN
			SELECT 	@ErrMsg = 'Delete failed. Please try again.', @ErrCode = 530	
			RETURN
		END
	END

	-- Write Log
	EXEC CustDB.dbo.NAP_SpecialCustSetting_WriteLog_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIP
		,@LicenseeID	= 0
		,@CurrencyID	= 0
		,@SPName		= 'LA_DiscountAssignmentSettingDel'
		,@CustId		= 0
		,@Duration		= @duration
		,@Data			= @logSPData
		,@OldData		= @logSPDataOld
END
GO