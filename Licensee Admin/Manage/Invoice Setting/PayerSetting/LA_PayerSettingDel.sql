/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_PayerSettingDel]	 
	@PayerId			INT
	, @PayerGroup		INT				= 0
	, @UserId			INT	
	, @LoginIp			VARCHAR (50)	= ''
	, @ErrCode			INT				= 0		OUTPUT
	, @ErrMsg			VARCHAR(4000)	= ''	OUTPUT	
AS
/*  
	 Created: 20150420@Florent
	 Task : Delete payer Setting
	 DB: DBCUST.bodb_Licensee  
   
	 Revisions:     
		- 20180716@bruce: add new group TEST for credit [#98126]
		
	 Params:		

	 Example:
		
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @startRun DATETIME, @endRun	DATETIME, @duration INT, @logSPData VARCHAR(5000), @logSPDataOld VARCHAR(5000),	@xml XML	
	SET @startRun = GETDATE()
	DECLARE @ProductListAll		VARCHAR(100) = ''		
		, @MinDate				DATE 
		, @MaxDate				DATE
		, @DiscountGroupId		INT
		, @RebaseGroupId		INT

	DECLARE @Minfee AS TABLE(Idx INT IDENTITY(1,1), MinfeeId INT, PartyId INT)
	DECLARE @Discount AS TABLE(Idx INT IDENTITY(1,1), DiscountGroupId INT, PartyId INT)
	DECLARE @ChargeDetail AS TABLE (Idx INT IDENTITY(1,1), ChargeID INT, PartyID INT, ProductID INT, DI_Rate MONEY, Fromdate DATE, Todate DATE)
	
	--get list Product
	SELECT @ProductListAll = @ProductListAll + ProductPrefix + ','
	FROM dbo.LA_f_Products3rd('')
	SET @ProductListAll = REPLACE(SUBSTRING(@ProductListAll, 0, LEN(@ProductListAll)), 'RB', '')

	--get Minium date, maximum date
	SELECT @MinDate = MIN(ci.FromDate)
		, @MaxDate = MAX(ci.ToDate)
	FROM dbo.OAS_ChargeInfo ci WITH (NOLOCK)
		INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2

	INSERT INTO @ChargeDetail(ChargeID, PartyID, ProductID, DI_Rate, Fromdate, Todate)
	SELECT ChargeID, PartyID, ProductID, DI_Rate, Fromdate, Todate
	FROM dbo.LA_f_ChargeInfo(@PayerId, @MinDate, @MaxDate, @ProductListAll, 'OA', 1)

	INSERT INTO @Minfee(MinfeeId, PartyId)
	SELECT MinFeeId, PartyId
	FROM dbo.LA_MinFee WITH (NOLOCK)
	WHERE PartyID = @PayerId

	INSERT INTO @Discount (DiscountGroupId, PartyId)
	SELECT a.DiscountGroupId, a.PartyID
	FROM dbo.LA_DiscountGroupAssignment a WITH (NOLOCK)		
	WHERE PartyID = @PayerId	

	-- validate PayerSetting
	-- validate charge rate of Payer
	EXEC dbo.LA_ChargeRateValidate 
		@PayerIdList = @PayerId
		, @Mode = 'R'
		, @ErrCode = @ErrCode OUTPUT
		, @ErrMsg = @ErrMsg OUTPUT
	IF @ErrCode <> 0 
	BEGIN 
		RETURN
	END
	-- validate Minfee
	EXEC dbo.LA_MinFeeValidate
		@PayerIdList = @PayerId
		, @Mode = 'R'
		, @ErrCode = @ErrCode OUTPUT
		, @ErrMsg = @ErrMsg OUTPUT
	IF @ErrCode <> 0 
	BEGIN 
		RETURN
	END
	-- validate Discount		
	-- check discount 
	SELECT @DiscountGroupId = a.DiscountGroupId 
	FROM dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) 		
		INNER JOIN dbo.LA_DiscountGroupHeader h WITH (NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId AND h.DiscountGroupType = 1
	WHERE PartyID = @PayerId

	EXEC dbo.LA_Discount_ValidatePayerAssignment
		@DiscountGroupId = @DiscountGroupId
		, @PayerIdList = @PayerId
		, @Mode = 'R'
		, @ErrCode = @ErrCode OUTPUT
		, @ErrMsg = @ErrMsg OUTPUT
	IF @ErrCode <> 0 
	BEGIN 
		RETURN
	END

	-- check rebate
	SELECT @RebaseGroupId = a.DiscountGroupId 
	FROM dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) 		
		INNER JOIN dbo.LA_DiscountGroupHeader h WITH (NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId AND h.DiscountGroupType = 2
	WHERE PartyID = @PayerId

	EXEC dbo.LA_Discount_ValidatePayerAssignment
		@DiscountGroupId = @RebaseGroupId
		, @PayerIdList = @PayerId
		, @Mode = 'R'
		, @ErrCode = @ErrCode OUTPUT
		, @ErrMsg = @ErrMsg OUTPUT
	IF @ErrCode <> 0 
	BEGIN 
		RETURN
	END

	--Delete ChargeRate
	--Delete mapping
	DECLARE @i INT = 0
	WHILE (@i <= (SELECT MAX(Idx) FROM @ChargeDetail))
	BEGIN
		DECLARE @TempChargeId INT
		SELECT @TempChargeId = ChargeID FROM @ChargeDetail WHERE Idx = @i
		IF @TempChargeId IS NOT NULL
		BEGIN
			EXEC dbo.LA_ChargeRateSettingDel 
				@ChargeId	= @TempChargeId
				, @PayerId	= @PayerId
				, @UserID	= @UserId
				, @LoginIP	= @LoginIP
				, @ErrCode	= @ErrCode	OUTPUT	
				, @ErrMsg	= @ErrMsg	OUTPUT
			IF @ErrCode <> 0 
				RETURN			
		END
		SET @i = @i + 1 
	END	
	--Delete Minfee
	--Delete Waive
	SET @i = 0
	WHILE (@i <= (SELECT MAX(Idx) FROM @Minfee))
	BEGIN
		DECLARE @TempMinfeeId INT
		SELECT @TempMinfeeId = MinfeeId FROM @Minfee WHERE Idx = @i
		IF @TempMinfeeId IS NOT NULL
		BEGIN
			EXEC dbo.LA_MinFeeSettingDel 
				@MinfeeId	= @TempMinfeeId
				, @PayerId	= @PayerId
				, @UserID	= @UserId
				, @LoginIP	= @LoginIP
				, @ErrCode	= @ErrCode	OUTPUT	
				, @ErrMsg	= @ErrMsg	OUTPUT
			IF @ErrCode <> 0 
				RETURN			
		END
		SET @i = @i + 1 
	END	

	--Delete Discount
	--Delete Rebate
	SET @i = 0
	WHILE (@i <= (SELECT MAX(Idx) FROM @Discount))
	BEGIN
		DECLARE @TempDiscountGroupId INT
		SELECT @TempDiscountGroupId = DiscountGroupId FROM @Discount WHERE Idx = @i
		IF @TempDiscountGroupId IS NOT NULL
		BEGIN
			EXEC dbo.LA_DiscountAssignmentSettingDel 
				@DiscountId		= @TempDiscountGroupId
				, @PayerId		= @PayerId
				, @UserID		= @UserID
				, @LoginIP		= @LoginIP
				, @ErrCode		= @ErrCode	OUTPUT
				, @ErrMsg		= @ErrMsg	OUTPUT				
			IF @ErrCode <> 0 
				RETURN			
		END
		SET @i = @i + 1 
	END	
END			 	
GO