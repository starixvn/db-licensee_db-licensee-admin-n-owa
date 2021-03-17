/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210317@Parsons
	DB: DBCUST.bodb_Licensee
	Task: Change-BaseCurrency-Of-Licensee [#FeatureID 151466]
	Description: End Sportsbook settings & create a new one with a different charge rate
*/
USE bodb_Licensee 
GO

DECLARE @SB_ChargeInfoSettingData VARCHAR(MAX)= '<Root>
								<ChargeInfoSetting>
									<PartyId>14</PartyId>
									<PartyName>12Bet</PartyName>
									<Rate>0.1</Rate>
									<FromDate>20210301</FromDate>
									<ToDate>20500101</ToDate>
								</ChargeInfoSetting>
								<ChargeInfoSetting>
									<PartyId>72</PartyId>
									<PartyName>9Club</PartyName>
									<Rate>0.07</Rate>
									<FromDate>20210301</FromDate>
									<ToDate>20500101</ToDate>
								</ChargeInfoSetting>
							</Root>'
DECLARE @ToDate DATE = '2050-01-01', @CurrentDate DATE = GETDATE()

BEGIN -- Parse XML settings
	DECLARE @SB_ChargeInfoSettings	TABLE (PartyId INT, PartyName VARCHAR(50), Current_ChargeID INT, Rate MONEY, Remark NVARCHAR(400), FirstOfBilling DATE, BasisOfBilling NVARCHAR(500), ChargeType INT, FromDate DATE, ToDate DATE, BaseCurrencyID INT) 
	IF(@SB_ChargeInfoSettingData <> '')
BEGIN
	DECLARE @docHandler INT

	BEGIN TRY
		EXEC sp_xml_preparedocument @docHandler OUTPUT, @SB_ChargeInfoSettingData
		INSERT INTO @SB_ChargeInfoSettings(PartyId, PartyName, Rate, FromDate, ToDate)
		SELECT PartyId, PartyName, Rate, FromDate, ToDate
		FROM OPENXML(@docHandler, 'Root/ChargeInfoSetting')
		WITH (	PartyId	INT 'PartyId',
				PartyName VARCHAR(50) 'PartyName',
				Rate	MONEY 'Rate', 
				FromDate DATE 'FromDate',
				ToDate DATE 'ToDate')
	
		EXEC sp_xml_removedocument @docHandler
	END TRY
	BEGIN CATCH
		SELECT 'Charge info setting data invalid. Please try again.'
		RETURN
	END CATCH;
END
END

BEGIN -- Step 1. Find SB settings exactly
	UPDATE p
	SET	p.Current_ChargeID = ci_2.ChargeID,
		p.FirstOfBilling = ci_2.FirstOfBilling,
		p.BasisOfBilling = ci_2.BasisOfBilling,
		p.ChargeType = ci_2.ChargeType
	FROM @SB_ChargeInfoSettings p
	CROSS APPLY
	(
		SELECT TOP 1 ci.ChargeID, FirstOfBilling, BasisOfBilling, ChargeType
		FROM OAS_ChargeInfo ci WITH(NOLOCK)
		WHERE ci.ToDate >= @CurrentDate AND ci.FromParty = p.PartyID AND ci.ProductID = 0 -- SB only
		ORDER BY ToDate DESC
	) ci_2
END

BEGIN -- Step 2. End settings
	UPDATE ci
	SET ci.ToDate = DATEADD(DAY, -1, p.FromDate) 
	FROM OAS_ChargeInfo ci WITH (NOLOCK)
	INNER JOIN @SB_ChargeInfoSettings p ON ci.FromParty = p.PartyId
END

BEGIN -- Step 3. Add new with a different charge rate 
	-- 3.1 OAS_ChargeInfo
	SELECT 123
	-- 3.2 LA_ChargeInfo_SystemMapping
END