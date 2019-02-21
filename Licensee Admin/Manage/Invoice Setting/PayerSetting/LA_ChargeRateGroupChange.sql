/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_ChargeRateGroupChange]
  @GroupId			INT,
  @PartyId			INT,
  @EffectiveDate	DATE
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

	--Step2: Copy charge rates to new group with FromDate = Effective date, ToDate = 2050-01-01
		-- 2.1 OAS_ChargeInfo
	INSERT INTO [dbo].[OAS_ChargeInfo](ProductID, FromParty, ToParty, ParentChargeID, Rate, ChargeType, FromDate, ToDate, Remark, BaseCurrencyId, FirstOfBilling, BasisOfBilling)
	SELECT ProductID, FromParty, @GroupId, ParentChargeID, Rate, ChargeType, @EffectiveDate, ToDate, Remark, BaseCurrencyId, FirstOfBilling, BasisOfBilling
	FROM @ChangeRateTable
		-- 2.2 LA_ChargeInfo_SystemMapping
	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID, SystemID)
	SELECT ChargeID, 2
	FROM OAS_ChargeInfo WITH(NOLOCK)
	WHERE FromParty = @PartyId AND ToParty = @GroupId AND FromDate = @EffectiveDate
	
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
END
GO