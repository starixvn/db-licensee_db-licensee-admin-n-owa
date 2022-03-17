/*<info serverAlias="DBLIC-bodb_licensee"></info>*/

/*
	Created: 20220316@Danny
	DB: DBLIC.bodb_licensee
	Description: Create table structure And Initialize data
*/
GO
-- DROP TABLE LA_VendorPaymentSetting
CREATE TABLE [dbo].[LA_VendorPaymentSetting](
	ProductId								INT				NOT NULL,
	ReportFunctionKey						NVARCHAR(50)	NULL,
	TemplateID								SMALLINT		NULL,
	TimezoneIDs								VARCHAR(50)		NULL,
	IsConvertNegativeFeeToZero				BIT				NULL,
	IsConvertNegativePaytoSupplierToZero	BIT				NULL,
	IsActive								BIT				NULL,
	 CONSTRAINT [PK_LA_VendorPaymentSetting] PRIMARY KEY CLUSTERED 
	(
		[Productid] ASC
	)
)

INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (2, 'vendorpayment_NG', 2, '1', 0, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (5, 'vendorpayment_VS', 3, '1', 1, 1, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (8, 'vendorpayment_KN', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (10, 'vendorpayment_AGC', 1, '1', 1, 1, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (15, 'vendorpayment_CB', 8, '1', 0, 0, 0)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (21, 'vendorpayment_AB', 9, '1,2', 0, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (22, 'vendorpayment_VB', 1, '1', 1, 1, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (23, 'vendorpayment_NG2', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (24, 'vendorpayment_FW', 1, '1,2', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (27, 'vendorpayment_VS2', 1, '1', 1, 1, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (28, 'vendorpayment_LT', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (31, 'vendorpayment_BX', 4, '1', 0, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (32, 'vendorpayment_PP', 5, '1,0', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (34, 'vendorpayment_CC', 6, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (36, 'vendorpayment_SG', 1, '1,2', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (39, 'vendorpayment_SAG', 10, '1,2', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (40, 'vendorpayment_TG', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (45, 'vendorpayment_SXG', 6, '1,2', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (46, 'vendorpayment_IBCLC', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (47, 'vendorpayment_BBIN', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (49, 'vendorpayment_VS3', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (50, 'vendorpayment_RNGW', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (51, 'vendorpayment_WM', 1, '1,2', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (52, 'vendorpayment_ION', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (55, 'vendorpayment_PGS', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (56, 'vendorpayment_JK', 1, '1,2', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (57, 'vendorpayment_BGG', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (59, 'vendorpayment_GDG', 7, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (60, 'vendorpayment_MXG', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (61, 'vendorpayment_HB', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (62, 'vendorpayment_CG', 1, '1,2', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (65, 'vendorpayment_PPL', 1, '0,1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (67, 'vendorpayment_AP', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (68, 'vendorpayment_APM', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (69, 'vendorpayment_BTC', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (70, 'vendorpayment_FGGL', 1, '1,2',1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (1000, 'vendorpayment_BetBuilder', 11, '1', 1, 0, 1) -- betBuilder
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (1001, 'vendorpayment_MuayThai', 12, '1', 0, 0, 1) -- MuayThai
GO
