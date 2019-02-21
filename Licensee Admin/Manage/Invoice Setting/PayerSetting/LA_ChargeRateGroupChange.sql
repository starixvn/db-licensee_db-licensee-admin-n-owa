/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_ChargeRateGroupChange]
	@GroupId		INT,
	@PartyId		INT,
	@EffectiveDate	DATE,
	@UserId			INT = 0,
	@ErrCode		INT				= 0		OUTPUT,
	@ErrMsg			NVARCHAR(1000)	= ''	OUTPUT
AS
/*
  Created: 20190221@Parsons
  Task : Get Payer setting
  DB: DB052.bodb_Licensee

  Revisions:
  - 20190221@Parsons: Manage Payer Setting - changing party group [#109189]

  Params:
  Example:
*/
BEGIN
	SET NOCOUNT ON

	DECLARE		@StartRun		DATETIME,
				@EndRun			DATETIME,
				@Duration		INT,
				@LogSPData		VARCHAR(5000),
				@LogSPDataOld	VARCHAR(5000),
				@Doing			NVARCHAR(MAX)
	
	SET @StartRun = GETDATE()

	DECLARE @ChangeRateTable AS TABLE(ChargeID INT, ProductID INT, FromParty INT, ToParty INT, ParentChargeID INT, Rate MONEY, ChargeType TINYINT, FromDate DATE, ToDate DATE, Remark NVARCHAR(200), BaseCurrencyId TINYINT, FirstOfBilling DATE, BasisOfBilling NVARCHAR(4000))
	
	INSERT INTO @ChangeRateTable(ChargeID, ProductID, FromParty, ToParty, ParentChargeID, Rate, ChargeType, FromDate, ToDate, Remark, BaseCurrencyId, FirstOfBilling, BasisOfBilling)
	SELECT ChargeID, ProductID, FromParty, ToParty, ParentChargeID, Rate, ChargeType, FromDate, ToDate, Remark, BaseCurrencyId, FirstOfBilling, BasisOfBilling
	FROM OAS_ChargeInfo WITH(NOLOCK)
	WHERE FromParty = @PartyId AND ToParty IN (1,9,11,98)
		  AND FromDate < @EffectiveDate AND ToDate > @EffectiveDate

	--Step1: Expire all active charge rates at EffectiveDate - 1
	UPDATE c1
	SET ToDate = DATEADD(DAY, -1, @EffectiveDate)
	FROM OAS_ChargeInfo c1 WITH(NOLOCK) 
	INNER JOIN @ChangeRateTable c2 ON c1.ChargeID = c2.ChargeID 
	
	IF @@Error > 0
	BEGIN
		UPDATE c1
		SET c1.ToDate = c2.ToDate
		FROM OAS_ChargeInfo c1
		INNER JOIN @ChangeRateTable c2 ON c1.ChargeID = c2.ChargeID

		SELECT @ErrMsg = 'Fail to expire all active charge rates', @ErrCode = 504
		RETURN
	END

	--Step2: Copy charge rates to new group with FromDate = Effective date
		-- 2.1 OAS_ChargeInfo
	INSERT INTO OAS_ChargeInfo(ProductID, FromParty, ToParty, ParentChargeID, Rate, ChargeType, FromDate, ToDate, Remark, BaseCurrencyId, FirstOfBilling, BasisOfBilling)
	SELECT ProductID, FromParty, @GroupId, ParentChargeID, Rate, ChargeType, @EffectiveDate, ToDate, Remark, BaseCurrencyId, FirstOfBilling, BasisOfBilling
	FROM @ChangeRateTable
		-- 2.2 LA_ChargeInfo_SystemMapping
	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID, SystemID)
	SELECT ChargeID, 2
	FROM OAS_ChargeInfo WITH(NOLOCK)
	WHERE FromParty = @PartyId AND ToParty = @GroupId AND FromDate = @EffectiveDate

	IF @@Error > 0
	BEGIN
		UPDATE c1
		SET c1.ToDate = c2.ToDate
		FROM OAS_ChargeInfo c1
		INNER JOIN @ChangeRateTable c2 ON c1.ChargeID = c2.ChargeID
		
		DELETE OAS_ChargeInfo
		WHERE FromParty = @PartyId AND ToParty = @GroupId AND FromDate = @EffectiveDate

		SELECT @ErrMsg = 'Fail to copy charge rates to new group', @ErrCode = 504
		RETURN
	END

	/*Step3: Special case, 
		ex: FromDate: 5
			ToDate: 10
			EffectiveDate: 5
		=> Need only to update group
	*/
	UPDATE OAS_ChargeInfo
	SET ToParty = @GroupId
	WHERE FromParty = @PartyId AND ToParty IN (1,9,11,98)
		  AND FromDate > DATEADD(DAY, -1, @EffectiveDate)
	
	SET @EndRun = GETDATE()
	SET @Duration = DATEDIFF (MILLISECOND, @StartRun, @EndRun)

	SET @Doing =(SELECT	@GroupId		AS GroupId,
						@PartyId		AS PartyId,
						@EffectiveDate	AS [EffectiveDate],
						@UserId			AS	UserId
						FOR XML PATH('')) 

	EXEC DBLOG.bodb_CustomerLog.dbo.WriteLog_UserLog_UserControl
		@Custid = 0,
		@Doing = @Doing,
		@Userid = @UserId,
		@Typeid = 0,
		@Actionid = 999,
		@Duration = @Duration

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = ERROR_MESSAGE() , @ErrCode = 506
	END
END
GO