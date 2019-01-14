/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_LaunchLicensee_ChargeInfoIns]
	@PartyId				INT,
	@BaseCurrencyId			TINYINT,
	@LaunchDate				DATE, 
	@Minfee					MONEY,
	@Waivemonth				TINYINT,
	@GroupId				INT,
	@ProductIds				VARCHAR(1000)	= '', 
	@ChargeInfoSettingData	VARCHAR(MAX)
AS
/*
	Created: 20190107@Parsons
	Task : Launch new licensee
	DB: DB052.bodb_Licensee

	Revisions:
	- 20190107@Parsons: Launch new licensee

	Param's Explannation: 
						@ChargeInfoSettingData = '<Root>
								<ChargeInfoSetting>
									<ProductId>0</ProductId>
									<Rate>0.15</Rate>
									<Remark>create date 2019-01-08</Remark>
									<BasisOfBilling>15% of Gross Win Launched on 2019-01-08</BasisOfBilling>
									<ChargeType>1</ChargeType>
									<FromDate>20190108</FromDate>
									<ToDate>20500101</ToDate>
								</ChargeInfoSetting>
								<ChargeInfoSetting>
									<ProductId>1</ProductId>
									<Rate>0.1</Rate>
									<Remark>create date 2019-01-08</Remark>
									<BasisOfBilling>10% of Gross Win Launched on 2019-01-08</BasisOfBilling>
									<ChargeType>1</ChargeType>
									<FromDate>20190108</FromDate>
									<ToDate>20500101</ToDate>
								</ChargeInfoSetting>
							</Root>'
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @Products	TABLE (ProductId INT)
	DECLARE @ChargeInfoSettings	TABLE (ProductId INT, Rate MONEY, Remark NVARCHAR(400), BasisOfBilling NVARCHAR(500), ChargeType INT, FromDate DATE, ToDate DATE) 
	
	INSERT INTO @Products(ProductId)
	SELECT val FROM bodb02.dbo.strSplit(@ProductIds, ',')

	IF(@ChargeInfoSettingData <> '')
	BEGIN
		DECLARE @docHandler INT
		
		EXEC sp_xml_preparedocument @docHandler OUTPUT, @ChargeInfoSettingData
		INSERT INTO @ChargeInfoSettings(ProductId, Rate, Remark, BasisOfBilling, ChargeType, FromDate, ToDate)
		SELECT ProductId, Rate, Remark,  BasisOfBilling, ChargeType, FromDate, ToDate
		FROM OPENXML(@docHandler, 'Root/ChargeInfoSetting')
		WITH (ProductId	INT 'ProductId', 
				Rate	MONEY 'Rate', 
				Remark	NVARCHAR(400) 'Remark', 
				BasisOfBilling NVARCHAR(500) 'BasisOfBilling',
				ChargeType INT 'ChargeType',
				FromDate DATE 'FromDate',
				ToDate DATE 'ToDate')
	
		EXEC sp_xml_removedocument @docHandler
	END
	
	-- #Region OAS_ChargeInfo & LA_ChargeInfo_SystemMapping
	INSERT INTO dbo.OAS_ChargeInfo (ProductID, FromParty, ToParty, ParentChargeID, Rate, Remark, BasisOfBilling, ChargeType, FromDate, ToDate, BaseCurrencyId)
	SELECT ProductId, @PartyId, @GroupId, 0, Rate, Remark, BasisOfBilling, ChargeType, FromDate, ToDate, @BaseCurrencyId
	FROM @ChargeInfoSettings

	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID, SystemID)
	SELECT c1.ChargeID, 2
	FROM dbo.OAS_ChargeInfo c1 WITH(NOLOCK)
		INNER JOIN @ChargeInfoSettings c2  ON c1.FromParty = @PartyId AND c1.ToParty = @GroupId AND c1.ProductID = c2.ProductId AND c1.ChargeType = c2.ChargeType
	-- #Endregion OAS_ChargeInfo & LA_ChargeInfo_SystemMapping

	-- #Region LA_MinFee
	IF(EXISTS(SELECT ProductId FROM @Products WHERE ProductId = 0))
	BEGIN
		IF(ISNULL(@Minfee, 0) > 0)
		BEGIN
			DECLARE @MinFeeID INT, @AMF MONEY

			INSERT INTO dbo.LA_MinFee(PartyId, FeeTypeId, ProductId, FeeAmount, CurrencyId, FromDate, ToDate, MinFeeTerm, [Priority])
			VALUES(@PartyId, 1, 0, @Minfee, @BaseCurrencyId, @LaunchDate, '20500101', 'EUR 5,000 (Waived for the first 3 months after launched)', 1)

			SELECT @MinFeeID = SCOPE_IDENTITY()

			-- Caculate Month of Deduction
			SELECT @AMF = SUM(ISNULL(d.Income, 0))
			FROM dbo.LA_InvoiceHeader h WITH (NOLOCK)
				INNER JOIN dbo.LA_InvoiceStatement d WITH (NOLOCK) ON h.InvoiceHeaderId = d.InvoiceHeaderId
			WHERE h.InvoiceType = 7 AND d.InvItemTypeId = 3 AND h.StatusId = 0 AND h.Environment = 'PRO'					
			AND h.PartyId = @PartyId
			AND h.CurrencyId = @BaseCurrencyId

			IF ISNULL(@AMF, 0) <> 0
			BEGIN
				UPDATE dbo.LA_MinFee
				SET MonthOfDeduction = CEILING(@AMF / @Minfee)
				WHERE MinFeeId = @MinFeeID
			END
		END

		IF(ISNULL(@Waivemonth, 0) > 0)
		BEGIN
			INSERT INTO dbo.LA_MinFee(PartyId, FeeTypeId, ProductId, FeeAmount, CurrencyId, FromDate, ToDate, MinFeeTerm, [Priority])
			VALUES(@PartyId, 2, 0, NULL, @BaseCurrencyId, @LaunchDate, DATEADD(DAY, - 1, DATEADD(MONTH, @WaiveMonth, @LaunchDate)), '', 2)
		END
	END
	-- #Endregion LA_MinFee
END
GO