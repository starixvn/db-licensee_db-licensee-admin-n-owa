/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_GroupMinFeeIns]
	@GroupName					NVARCHAR(110),
	@FromDate					DATE,
	@ToDate						DATE,
	@LicenseeSettingData		NVARCHAR(MAX),
	@GroupMinFeeSettingData		NVARCHAR(MAX),
	@ErrCode					INT				= 0		OUTPUT, 
	@ErrMsg						VARCHAR(4000)	= ''	OUTPUT,
	@NewGroupMinFeeId			SMALLINT = 0 			OUTPUT
AS
/*
	Created: 20200630@Happy
	Task : Insert new GroupMinFee
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20200630@Happy: Implement Group Min Fee [#134492]

	Param's Explannation: 
						@LicenseeSettingData = '<Root>
							<LicenseeSetting>
								<PartyID>1</PartyID>
								<IsPrimary>1</IsPrimary>
							</LicenseeSetting>
							<LicenseeSetting>
								<PartyID>2</PartyID>
								<IsPrimary>0</IsPrimary>
							</LicenseeSetting>
						</Root>'
						
						@GroupMinFeeSettingData = '<Root>
							<GroupMinFeeSetting>
								<ProductId>0</ProductId>
								<MinimumFee>5000</MinimumFee>
								<MinimumFeeTerm>EUR 5,000 (Waived for the first 3 months after launched)</MinimumFeeTerm>
								<CurrencyId>6</CurrencyId>
								<FromDate>20190108</FromDate>
								<ToDate>20500101</ToDate>
							</GroupMinFeeSetting>
							<GroupMinFeeSetting>
								<ProductId>0</ProductId>
								<MinimumFee>2</MinimumFee>
								<MinimumFeeTerm />
								<CurrencyId>6</CurrencyId>
								<FromDate>20190108</FromDate>
								<ToDate>20190407</ToDate>
							</GroupMinFeeSetting>
						</Root>'
*/
BEGIN
	SET NOCOUNT ON;
	EXEC dbo.LA_GroupMinFeeHeaderIns @GroupName, @FromDate, @ToDate, @NewGroupMinFeeId OUTPUT, @ErrCode OUTPUT, @ErrMsg OUTPUT
	
	IF @ErrCode = 0
	BEGIN
		EXEC dbo.LA_GroupMinFeeAssignmentIns @NewGroupMinFeeId, @LicenseeSettingData, @ErrCode OUTPUT, @ErrMsg OUTPUT
	END
	
	IF @ErrCode = 0
	BEGIN
		EXEC dbo.LA_GroupMinFeeDetailIns @NewGroupMinFeeId, @GroupMinFeeSettingData, @ErrCode OUTPUT, @ErrMsg OUTPUT
	END
	
	IF @ErrCode <> 0
	BEGIN
		EXEC dbo.LA_GroupMinFeeIns_RollBack @NewGroupMinFeeId
		RETURN
	END
END
GO