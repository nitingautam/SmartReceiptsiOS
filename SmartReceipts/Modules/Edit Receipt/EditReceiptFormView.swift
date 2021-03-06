//
//  EditReceiptFormView.swift
//  SmartReceipts
//
//  Created by Bogdan Evsenev on 18/06/2017.
//  Copyright © 2017 Will Baumann. All rights reserved.
//

import Eureka
import RxSwift
import RxCocoa

class EditReceiptFormView: FormViewController, QuickAlertPresenter {
    
    private let CURRENCY_ROW_TAG = "CurrencyRow"
    private let NAME_ROW_TAG = "NameRow"
    private let EXCHANGE_RATE_TAG = "ExchangeRateRow"
    private let COMMENT_ROW_TAG = "CommentRow"
    private let PAYMENT_METHODS_ROW_TAG = "PaymentMethodsRow"
    private let CATEGORIES_ROW_TAG = "CategoriesRow"
    private let PRICE_ROW_TAG = "PriceRow"
    private let TAX_ROW_TAG = "TaxRow"
    private let TAX_PICKER_ROW_TAG = "TaxPickerRow"
    
    let receiptSubject = PublishSubject<WBReceipt>()
    let errorSubject = PublishSubject<String>()
    weak var settingsTap: PublishSubject<Void>?
    weak var manageCategoriesTap: Observable<Void>?
    weak var managePaymentMethodsTap: Observable<Void>?
    var needFirstResponder = true
    
    private var isNewReceipt = false
    private var hasScan = false
    private var receipt: WBReceipt!
    private var trip: WBTrip!
    private var taxCalculator: TaxCalculator?
    private let bag = DisposeBag()
    private var canShowTaxPicker = false
    
    init(trip: WBTrip, receipt: WBReceipt?) {
        super.init(nibName: nil, bundle: nil)
        self.trip = trip
        isNewReceipt = receipt == nil
        if isNewReceipt {
            self.receipt = WBReceipt()
            self.receipt.setPrice(NSDecimalNumber.zero, currency: trip.defaultCurrency.code)
            self.receipt.date = Date()
            self.receipt.category =  Database.sharedInstance().category(byName: proposedCategory())
            self.receipt.exchangeRate = NSDecimalNumber.zero
            self.receipt.isReimbursable = WBPreferences.expensableDefault()
            self.receipt.isFullPage = WBPreferences.assumeFullPage()
            self.receipt.timeZone = TimeZone.current
            
            if let pm = Database.sharedInstance().allPaymentMethods().last {
                self.receipt.paymentMethod = pm
            }
        } else {
            self.receipt = receipt!.copy() as! WBReceipt
        }
        
        // Check conditions for automatic tax calculator
        if WBPreferences.includeTaxField() && WBPreferences.defaultTaxPercentage() != 0 && isNewReceipt {
            taxCalculator = TaxCalculator(preTax: WBPreferences.enteredPricePreTax())
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let exchangeRow = form.rowBy(tag: EXCHANGE_RATE_TAG) as? ExchangeRateRow {
            exchangeRow.responseSubject.onNext(ExchangeResponse(value: nil, error: nil))
            exchangeRow.cell.update()
        }
        
        if let paymentMethodsRow = form.rowBy(tag: PAYMENT_METHODS_ROW_TAG) as? InlinePickerButtonRow {
            paymentMethodsRow.options = Database.sharedInstance().allPaymentMethodsAsStrings()
        }
        
        if let categoriesRow = form.rowBy(tag: CATEGORIES_ROW_TAG) as? InlinePickerButtonRow {
            categoriesRow.options = allCategories()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        form
        +++ Section()
        <<< PredectiveTextRow(NAME_ROW_TAG) { row in
            row.title = LocalizedString("RECEIPTMENU_FIELD_NAME")
            row.placeholder = LocalizedString("edit.receipt.name.placeholder")
            row.value = receipt.name
        }.onChange({ [unowned self] row in
            self.receipt.name = row.value ?? ""
        }).cellSetup({ [unowned self] cell, _ in
            cell.configureCell()
            if self.needFirstResponder {
                cell.textField.becomeFirstResponder()
            }
            if WBPreferences.isAutocompleteEnabled() {
                cell.enableAutocompleteHelper()
            }
        })
    
        <<< DecimalRow(PRICE_ROW_TAG) { row in
            row.title = LocalizedString("RECEIPTMENU_FIELD_PRICE")
            row.placeholder = LocalizedString("edit.receipt.price.placeholder")
            row.value = receipt.price().amount.doubleValue != 0 ?
                receipt.price().amount.doubleValue : nil
        }.onChange({ [unowned self] row in
            if let dec = row.value {
                let amount = NSDecimalNumber(value: dec)
                self.receipt.setPrice(amount, currency: self.receipt.currency.code)
                self.taxCalculator?.priceSubject.onNext(Decimal(dec))
            } else {
                self.taxCalculator?.priceSubject.onNext(nil)
            }
            self.updateTaxPicker()
        }).cellSetup({ cell, _ in
            cell.configureCell()
            cell.textField.inputView = NumberKeyboard.create(delegate: cell.textField)
        })
            
        <<< DecimalRow(TAX_ROW_TAG) { [unowned self] row in
            row.hidden = Condition(booleanLiteral: !WBPreferences.includeTaxField())
            row.title = LocalizedString("RECEIPTMENU_FIELD_TAX")
            row.placeholder = LocalizedString("edit.receipt.tax.placeholder")
            row.value = self.isNewReceipt && !self.hasScan ? nil : self.receipt.taxAmount?.doubleValue
            
            if let calculator = self.taxCalculator {
                calculator.taxSubject.subscribe(onNext: {
                    row.value = Double(string: $0)
                    row.updateCell()
                }).disposed(by: self.bag)
            }
        }.onChange({ [unowned self] row in
            self.receipt.setTax(NSDecimalNumber(value: row.value ?? 0))
        }).cellSetup({ cell, _ in
            cell.configureCell()
            cell.textField.inputView = NumberKeyboard.create(delegate: cell.textField)
        }).onCellHighlightChanged({ [unowned self] cell, _ in
            self.updateTaxPicker()
            self.canShowTaxPicker = cell.textField.isFirstResponder
            self.form.rowBy(tag: self.TAX_PICKER_ROW_TAG)?.evaluateHidden()
        })
            
        <<< HorizontalPickerRow(TAX_PICKER_ROW_TAG) { row in
            row.hidden = Condition.function([], { [unowned self] _ in return self.needShowTaxPicker() })
        }.onChange({ row in
            if let index = row.value {
                let percent = self.taxPercents()[index]
                self.setValue(cellTag: self.TAX_ROW_TAG, value: self.calculateTax(percent: percent))
            }
            row.evaluateHidden()
        })
        
        <<< PickerInlineRow<String>(CURRENCY_ROW_TAG) { row in
            row.title = LocalizedString("pref_general_default_currency_title")
            row.options = Currency.allCurrencyCodesWithCached()
            row.value = receipt.currency.code
        }.onChange({ [unowned self] row in
            if let code = row.value {
                self.receipt.setPrice(self.receipt.priceAmount, currency: code)
                if code != self.trip.defaultCurrency.code {
                    self.updateExchangeRate()
                }
            }
        }).cellSetup({ cell, _ in
            cell.configureCell()
        })
            
        <<< ExchangeRateRow(EXCHANGE_RATE_TAG) { row in
            row.title = LocalizedString("column_item_exchange_rate")
            row.hidden = Condition.function([CURRENCY_ROW_TAG], { [unowned self] form -> Bool in
                if let picker = form.rowBy(tag: self.CURRENCY_ROW_TAG) as? PickerInlineRow<String> {
                    return picker.value == self.trip.defaultCurrency.code
                } else {
                    return false
                }
            })
            row.value = receipt.exchangeRate?.doubleValue
            row.updateTap.subscribe(onNext: { [unowned self] in self.updateExchangeRate() })
                .disposed(by: self.bag)
        }.onChange({ [unowned self] row in
            self.receipt.exchangeRate = NSDecimalNumber(value: row.value ?? 0)
        }).cellSetup({ [unowned self] cell, row in
            cell.alertPresenter = self
        })
        
        <<< DateInlineRow() { row in
            row.title = LocalizedString("RECEIPTMENU_FIELD_DATE")
            row.value = receipt.date
            row.dateFormatter?.timeZone = receipt.timeZone
        }.onChange({ [unowned self] row in
            self.receipt.date = row.value ?? Date()
        }).cellSetup({ cell, _ in
            cell.configureCell()
        }).onExpandInlineRow({ _, _, datePickerRow in
            datePickerRow.cell.datePicker.timeZone = self.receipt.timeZone
        })
        
        <<< InlinePickerButtonRow(CATEGORIES_ROW_TAG) { [unowned self] row in
            row.title = LocalizedString("filter_name_receipt_category")
            row.options = allCategories()
            row.value = receipt.category?.name ?? ""
            row.buttonTitle = LocalizedString("manage_categories").uppercased()
            self.manageCategoriesTap = row.buttonTap
        }.onChange({ [unowned self] row in
            self.receipt.category = Database.sharedInstance().category(byName: row.value!)
            self.matchCategory(value: row.value)
        })
        
        <<< TextRow(COMMENT_ROW_TAG) { row in
            row.title = LocalizedString("RECEIPTMENU_FIELD_COMMENT")
            row.placeholder = LocalizedString("edit.receipt.comment.placeholder")
            row.value = receipt.comment
        }.onChange({ [unowned self] row in
            self.receipt.comment = row.value ?? ""
        }).cellSetup({ cell, _ in
            cell.configureCell()
        })
            
        <<< InlinePickerButtonRow(PAYMENT_METHODS_ROW_TAG) { [unowned self] row in
            row.title = LocalizedString("payment_method")
            row.options = Database.sharedInstance().allPaymentMethodsAsStrings()
            row.value = receipt.paymentMethod.method
            row.hidden = Condition.init(booleanLiteral: !WBPreferences.usePaymentMethods())
            row.buttonTitle = LocalizedString("manage_payment_methods").uppercased()
            self.managePaymentMethodsTap = row.buttonTap
        }.onChange({ [unowned self] row in
            if let name = row.value, let pm = Database.sharedInstance().paymentMethod(byName: name) {
                self.receipt.paymentMethod = pm
            }
        })
            
        <<< CheckRow() { row in
            row.title = LocalizedString("graphs_label_reimbursable")
            row.value = receipt.isReimbursable
        }.onChange({ [unowned self] row in
            self.receipt.isReimbursable = row.value!
        }).cellSetup({ cell, _ in
            cell.configureCell()
            cell.tintColor = AppTheme.primaryColor
        })

        <<< CheckRow() { row in
            row.title = LocalizedString("edit.receipt.full.page.label")
            row.value = receipt.isFullPage
        }.onChange({ [unowned self] row in
            self.receipt.isFullPage = row.value!
        }).cellSetup({ cell, _ in
            cell.configureCell()
            cell.tintColor = AppTheme.primaryColor
        })
        
        if isNewReceipt {
            matchCategory(value: receipt.category?.name)
        }
    }
    
    func apply(scan: Scan?) {
        guard let gScan = scan else { return }
        hasScan = true
        receipt.name = gScan.merchant ?? ""
        receipt.date = gScan.date ?? Date()
        
        if let amount = gScan.totalAmount {
            receipt.setPrice(NSDecimalNumber(value: amount), currency: trip.defaultCurrency.code)
        }
        
        if let tax = gScan.taxAmount, WBPreferences.includeTaxField()  {
            if let amount = gScan.totalAmount, WBPreferences.enteredPricePreTax() {
                receipt.setPrice(NSDecimalNumber(value: amount - tax), currency: trip.defaultCurrency.code)
            }
            receipt.setTax(NSDecimalNumber(value: tax))
        }
    }
    
    func validate() {
        receipt.trip = trip
        receiptSubject.onNext(receipt)
    }
    
    func makeNameFirstResponder() {
        if let nameRow = form.rowBy(tag: NAME_ROW_TAG) as? PredectiveTextRow {
            nameRow.cell.textField.becomeFirstResponder()
        }
    }
    
    private func needShowTaxPicker() -> Bool {
        if let priceRow = form.rowBy(tag: PRICE_ROW_TAG) as? DecimalRow,
           let price = priceRow.value, price != 0, canShowTaxPicker {
            return false
        } else {
            return true
        }
    }
    
    private func setValue(cellTag: String, value: Any?) {
        form.rowBy(tag: cellTag)?.baseValue = value
        form.rowBy(tag: cellTag)?.updateCell()
    }
    
    private func matchCategory(value: String?) {
        if WBPreferences.matchNameToCategory() {
            setValue(cellTag: NAME_ROW_TAG, value: value)
        }
        
        if WBPreferences.matchCommentToCategory() {
            setValue(cellTag: COMMENT_ROW_TAG, value: value)
        }
    }
    
    func updateTaxPicker() {
        var taxOptions = [NSAttributedString]()
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        formatter.minimumIntegerDigits = 1
        
        for percent in taxPercents() {
            let calculatedTax = calculateTax(percent: percent)
            if let valueString = formatter.string(from: calculatedTax),
                let percentString = formatter.string(from: NSDecimalNumber(string: "\(percent)")) {
                let attributedString = NSMutableAttributedString(string: "\(valueString)  \(percentString)%")
                let range = NSRange(location: 0, length: valueString.count)
                attributedString.addAttribute(.font, value: AppTheme.boldFont, range: range)
                taxOptions.append(attributedString)
            }
        }
        
        let taxPickerRow = form.rowBy(tag: TAX_PICKER_ROW_TAG) as? HorizontalPickerRow
        taxPickerRow?.options = taxOptions
    }
    
    private func taxPercents() -> [Float] {
        let defaultTaxPercent = WBPreferences.defaultTaxPercentage()
        var percents = defaultTaxPercent != 0 ? [defaultTaxPercent] : [Float]()
        percents.append(contentsOf: [0, 5, 10, 20])
        return percents
    }
    
    private func calculateTax(percent: Float) -> NSDecimalNumber {
        let preTax = WBPreferences.enteredPricePreTax()
        let taxPercent = NSDecimalNumber(string: "\(percent)")
        let price = NSDecimalNumber(value: ((form.rowBy(tag: PRICE_ROW_TAG) as? DecimalRow)?.value ?? 0))
        let floatTax = TaxCalculator.taxWithPrice(price, taxPercentage: taxPercent, preTax: preTax).floatValue
        return NSDecimalNumber(string: String(format: "%.2f", floatTax))
    }
    
    private func updateExchangeRate() {
        if let exchangeRow = form.rowBy(tag: EXCHANGE_RATE_TAG) as? ExchangeRateRow {
            CurrencyExchangeService()
                .exchangeRate(trip.defaultCurrency.code, target: receipt.currency.code, onDate: receipt.date)
                .observeOn(MainScheduler.instance)
                .bind(to: exchangeRow.responseSubject)
                .disposed(by: bag)
        }
    }
    
    fileprivate func allCategories() -> [String] {
        var result = [String]()
        for category in Database.sharedInstance().listAllCategories() {
            result.append(category.name)
        }
        return result
    }
}

fileprivate extension BaseCell {
    fileprivate func configureCell() {
        textLabel?.font = AppTheme.boldFont
        detailTextLabel?.textColor = AppTheme.primaryColor
        detailTextLabel?.font = AppTheme.boldFont
    }
}

//MARK: Prepare Cells
fileprivate extension EditReceiptFormView {
    fileprivate func proposedCategory() -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour], from: Date())
        let hour = components.hour!
        
        let categories = allCategories()
        if categories.isEmpty {
            return ""
        }
        
        if WBPreferences.predictCategories() {
            var predictedCategory = String()
            if hour >= 4 && hour < 11 {
                predictedCategory = WBCategory.category_NAME_BREAKFAST()
            } else if hour >= 11 && hour < 16 {
                predictedCategory = WBCategory.category_NAME_LUNCH()
            } else if hour >= 16 && hour < 23 {
                predictedCategory = WBCategory.category_NAME_DINNER()
            }
            
            if categories.contains(predictedCategory) {
                return predictedCategory
            }
        }
        
        return categories.first!
    }
}
