/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_LaunchLicensee_ChargeInfoIns]
	@PartyId				INT,
	@GroupId				INT,
	@ChargeInfoSettingData	VARCHAR(MAX),
	@ErrCode			INT				= 0		OUTPUT, 
	@ErrMsg				VARCHAR(4000)	= ''	OUTPUT
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
									<BaseCurrencyID>6</BaseCurrencyID>
								</ChargeInfoSetting>
								<ChargeInfoSetting>
									<ProductId>1</ProductId>
									<Rate>0.1</Rate>
									<Remark>create date 2019-01-08</Remark>
									<BasisOfBilling>10% of Gross Win Launched on 2019-01-08</BasisOfBilling>
									<ChargeType>1</ChargeType>
									<FromDate>20190108</FromDate>
									<ToDate>20500101</ToDate>
									<BaseCurrencyID>6</BaseCurrencyID>
								</ChargeInfoSetting>
							</Root>'
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @ChargeInfoSettings	TABLE (ProductId INT, Rate MONEY, Remark NVARCHAR(400), BasisOfBilling NVARCHAR(500), ChargeType INT, FromDate DATE, ToDate DATE, BaseCurrencyID INT) 
	
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
				ToDate DATE 'ToDate',
				BaseCurrencyID INT 'BaseCurrencyID')
	
		EXEC sp_xml_removedocument @docHandler
	END
	
	-- #Region OAS_ChargeInfo & LA_ChargeInfo_SystemMapping
	INSERT INTO dbo.OAS_ChargeInfo (ProductID, FromParty, ToParty, ParentChargeID, Rate, Remark, BasisOfBilling, ChargeType, FromDate, ToDate, BaseCurrencyId)
	SELECT ProductId, @PartyId, @GroupId, 0, Rate, Remark, BasisOfBilling, ChargeType, FromDate, ToDate, BaseCurrencyId
	FROM @ChargeInfoSettings

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Insert OAS_ChargeInfo failed. Please try again.', @ErrCode =  503
		RETURN
	END

	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID, SystemID)
	SELECT c1.ChargeID, 2
	FROM dbo.OAS_ChargeInfo c1 WITH(NOLOCK)
		INNER JOIN @ChargeInfoSettings c2  ON c1.FromParty = @PartyId AND c1.ToParty = @GroupId AND c1.ProductID = c2.ProductId AND c1.ChargeType = c2.ChargeType
		
	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Insert LA_ChargeInfo_SystemMapping failed. Please try again.', @ErrCode =  503
		RETURN
	END
	-- #Endregion OAS_ChargeInfo & LA_ChargeInfo_SystemMapping
END
GO