/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_ChargeInfoIns]
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
								</ChargeInfoSetting>
								<ChargeInfoSetting>
									<ProductId>1</ProductId>
									<Rate>0.1</Rate>
									<Remark>create date 2019-01-08</Remark>
									<BasisOfBilling>10% of Gross Win Launched on 2019-01-08</BasisOfBilling>
									<ChargeType>1</ChargeType>
								</ChargeInfoSetting>
							</Root>'
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @Products	TABLE (ProductId INT)
	DECLARE @ChargeInfoSettings	TABLE (ProductId INT, Rate MONEY, Remark NVARCHAR(400), BasisOfBilling NVARCHAR(500), ChargeType INT) 
	
	INSERT INTO @Products(ProductId)
	SELECT val FROM bodb02.dbo.strSplit(@ProductIds, ',')

	IF(@ChargeInfoSettingData <> '')
	BEGIN
		DECLARE @docHandler INT
		
		EXEC sp_xml_preparedocument @docHandler OUTPUT, @ChargeInfoSettingData
		INSERT INTO @ChargeInfoSettings(ProductId, Rate, Remark, BasisOfBilling, ChargeType)
		SELECT ProductId, Rate, Remark,  BasisOfBilling, ChargeType
		FROM OPENXML(@docHandler, 'Root/ChargeInfoSetting')
		WITH (ProductId	INT 'ProductId', 
				Rate	MONEY 'Rate', 
				Remark	NVARCHAR(400) 'Remark', 
				BasisOfBilling NVARCHAR(500) 'BasisOfBilling',
				ChargeType INT 'ChargeType')
	
		EXEC sp_xml_removedocument @docHandler
	END
	
	-- #Region OAS_ChargeInfo & LA_ChargeInfo_SystemMapping
	DECLARE @ProductId INT, @Rate MONEY, @Remark NVARCHAR(400), @BasisOfBilling NVARCHAR(500), @ChargeType INT
	DECLARE @ChargeInfo_SystemMapping TABLE (ChargeID INT)
	WHILE(EXISTS(SELECT ProductId FROM @ChargeInfoSettings))
	BEGIN
		SELECT TOP 1 @ProductId = ProductId, @Rate = Rate, @Remark = Remark, @BasisOfBilling = BasisOfBilling, @ChargeType = ChargeType FROM @ChargeInfoSettings

		INSERT INTO dbo.OAS_ChargeInfo (ProductID, FromParty, ToParty, ParentChargeID, Rate, Remark, BasisOfBilling, ChargeType, FromDate, ToDate, BaseCurrencyId)
		VALUES(@ProductId, @PartyId, @GroupId, 0, @Rate, @Remark, @BasisOfBilling, @ChargeType, @LaunchDate, '20500101', @BaseCurrencyId)

		INSERT INTO @ChargeInfo_SystemMapping(ChargeID) VALUES(SCOPE_IDENTITY())

		DELETE @ChargeInfoSettings WHERE ProductId = @ProductId AND ChargeType = @ChargeType
	END

	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID, SystemID)
	SELECT ChargeID, 2
	FROM @ChargeInfo_SystemMapping
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